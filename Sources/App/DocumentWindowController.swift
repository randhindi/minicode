import AppKit
import WebKit
import UniformTypeIdentifiers

/// One window per document: an optional plain-text editor on the left and the
/// rendered page on the right. Opening a file shows only the page; ⌘E toggles the editor.
final class DocumentWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate, NSToolbarDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    private let splitController = NSSplitViewController()
    private var editorItem: NSSplitViewItem!
    private var previewItem: NSSplitViewItem!
    private let textView: CodeTextView
    private var colorizer: SyntaxColorizer!
    private let editorScroll: NSScrollView
    private let webView: WKWebView
    private var highlighted: (start: Int, end: Int)?
    private var suppressScrollSync = false
    private var applyingFromPage = false

    private var pageLoaded = false
    private var pageLayout: Page.Layout = .markdown
    private var previewStale = false
    private var frameBeforeEditing: NSRect?
    private var expandedFrame: NSRect?
    private var pendingBody: String?
    private var renderWork: DispatchWorkItem?
    private static let renderQueue = DispatchQueue(label: "markdown-render", qos: .userInitiated)
    private static var imageCache: [String: (Date, String)] = [:]

    // Kept separately from `document`: AppKit sets that itself in addWindowController,
    // and silently skips controllers whose `document` is already set.
    private weak var textDocument: TextDocument?

    private var isMarkdown: Bool { textDocument?.kind.isMarkdown ?? true }

    init(document: TextDocument, startEditing: Bool) {
        (editorScroll, textView) = CodeTextView.make()
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(WKUserScript(source: PageScript.source, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 420, height: 300)
        window.tabbingMode = .preferred
        super.init(window: window)

        configureEditor()
        webView.navigationDelegate = self
        config.userContentController.add(WeakScriptHandler(self), name: "select")
        // Let the window background show until the page paints (no white flash in dark mode).
        // There is no public API for this on macOS; the key has been stable since WKWebView shipped.
        webView.setValue(false, forKey: "drawsBackground")

        let editorVC = NSViewController(); editorVC.view = editorScroll
        let previewVC = NSViewController(); previewVC.view = webView
        editorItem = NSSplitViewItem(viewController: editorVC)
        editorItem.canCollapse = true
        editorItem.minimumThickness = 240
        editorItem.isCollapsed = !startEditing
        previewItem = NSSplitViewItem(viewController: previewVC)
        previewItem.canCollapse = true
        previewItem.isCollapsed = startEditing && !document.kind.isMarkdown // code edits full-width
        previewItem.minimumThickness = 240
        splitController.splitViewItems = [editorItem, previewItem]
        splitController.splitView.isVertical = true
        splitController.splitView.dividerStyle = .thin
        window.contentViewController = splitController
        window.setContentSize(Self.defaultContentSize)
        window.center() // first launch; afterwards the saved frame below wins

        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.delegate = self
        shouldCascadeWindows = true
        windowFrameAutosaveName = "Document"

        textDocument = document
        document.onReload = { [weak self] in self?.reloadFromDocument() }
        reloadFromDocument()
        if startEditing { window.makeFirstResponder(textView) }
    }

    required init?(coder: NSCoder) { fatalError() }

    /// New windows: 1100pt wide, and most of the screen's height (capped at 1200pt).
    private static var defaultContentSize: NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        return NSSize(width: min(1100, screen.width - 40), height: min(1200, (screen.height * 0.85).rounded()))
    }

    // MARK: - Editor

    private func configureEditor() {
        textView.configure()
        textView.delegate = self
        colorizer = SyntaxColorizer(textView: textView)
        editorScroll.verticalRulerView = LineNumberRuler(textView: textView)
        editorScroll.hasVerticalRuler = true

        editorScroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorScrolled),
                                               name: NSView.boundsDidChangeNotification, object: editorScroll.contentView)
    }

    /// Markdown gets the side-by-side editor; code gets line numbers and no wrapping.
    private func applyKind() {
        guard let doc = textDocument else { return }
        let kind = doc.kind
        colorizer.language = kind.language
        if case .code(let language) = kind { textView.wrapsLines = language == nil } else { textView.wrapsLines = true }
        editorScroll.rulersVisible = !kind.isMarkdown
        (editorScroll.verticalRulerView as? LineNumberRuler)?.refresh()
    }

    deinit { webView.configuration.userContentController.removeScriptMessageHandler(forName: "select") }

    // MARK: - Selection sync

    /// Editor → page. A caret highlights its block; a text selection selects the same text in the page.
    func textViewDidChangeSelection(_ notification: Notification) {
        guard !applyingFromPage, !editorItem.isCollapsed, isMarkdown else { return }
        let ns = textView.string as NSString
        let sel = textView.selectedRange()
        let start = lineNumber(at: sel.location)
        let end = sel.length > 0 ? lineNumber(at: sel.location + sel.length - 1) + 1 : start + 1
        let text = Self.plain(ns.substring(with: sel))
        guard !text.isEmpty else { return highlight(start, end, scroll: true) }

        // Context: plain text of the source just before the selection (from a couple of lines up).
        let contextStart = offset(ofLine: max(0, start - 2))
        let before = String(Self.plain(ns.substring(with: NSRange(location: contextStart, length: sel.location - contextStart))).suffix(40))
        highlighted = nil
        let args = [text, before].map(Self.jsString).joined(separator: ", ")
        webView.evaluateJavaScript("mdSelectText(\(start), \(end), \(args))") { [weak self] found, _ in
            if (found as? Bool) != true { self?.highlight(start, end, scroll: true) } // couldn't place it: fall back to the block
        }
    }

    private func highlight(_ start: Int, _ end: Int, scroll: Bool) {
        guard !editorItem.isCollapsed else { highlighted = nil; return } // only while editing
        highlighted = (start, end)
        webView.evaluateJavaScript("window.mdHighlight && mdHighlight(\(start), \(end), \(scroll))")
    }

    /// Turns click-to-select and the highlight on in the page only while the editor is showing.
    private func updateSelectionSync() {
        webView.evaluateJavaScript("window.mdSetSync && mdSetSync(\(!editorItem.isCollapsed && isMarkdown))")
    }

    /// Page → editor. The page sends the block's lines, the selected text (empty for a click) and the
    /// text just before it; we find that text in the source, skipping over Markdown syntax.
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let s = body["start"] as? Int, let e = body["end"] as? Int,
              let text = body["text"] as? String, let before = body["before"] as? String else { return }
        let ns = textView.string as NSString
        let blockStart = offset(ofLine: s)
        var blockEnd = offset(ofLine: e)
        if blockEnd > blockStart, ns.character(at: blockEnd - 1) == 10 { blockEnd -= 1 }
        let block = NSRange(location: blockStart, length: blockEnd - blockStart)

        var target = block // fallback: the whole block
        if !text.isEmpty {
            if let match = locate(text, before: before, in: block) { target = match }
        } else if let tail = before.split(separator: " ").last.map(String.init), !tail.isEmpty {
            // A click: find the word just before the caret and put the cursor after it.
            let rest = String(before.dropLast(tail.count))
            if let match = locate(tail, before: rest, in: block) { target = NSRange(location: NSMaxRange(match), length: 0) }
            if before.hasSuffix(" "), target.length == 0, target.location < NSMaxRange(block) { target.location += 1 }
        } else {
            target = NSRange(location: blockStart + contentIndent(of: ns.substring(with: block)), length: 0)
        }

        applyingFromPage = true
        suppressScrollSync = true
        textView.setSelectedRange(target)
        textView.scrollRangeToVisible(target)
        applyingFromPage = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.suppressScrollSync = false }
    }

    /// Finds `text` inside `range`, allowing Markdown syntax between characters; picks the
    /// occurrence whose preceding (plain) text best matches `before`.
    private func locate(_ text: String, before: String, in range: NSRange) -> NSRange? {
        let skip = #"(?:[*_~`]|\]\([^)\n]*\)|\[|<[^>\n]*>)*"#
        let pattern = text.map { c -> String in
            c.isWhitespace ? #"(?:\s|[*_~`>])+"# : NSRegularExpression.escapedPattern(for: String(c))
        }.joined(separator: skip)
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = textView.string as NSString
        var best: (NSRange, Int)?
        for m in regex.matches(in: textView.string, range: range) {
            let prefix = Self.plain(ns.substring(with: NSRange(location: range.location, length: m.range.location - range.location)))
            let score = zip(prefix.reversed(), before.reversed()).prefix { $0 == $1 }.count
            if best == nil || score > best!.1 { best = (m.range, score) }
        }
        return best?.0
    }

    /// Roughly what Markdown source looks like once rendered: syntax removed, whitespace collapsed.
    static func plain(_ source: String) -> String {
        var s = source
        for (pattern, template) in [(#"!?\[([^\]]*)\]\([^)]*\)"#, "$1"), (#"(?m)^\s{0,3}(?:#{1,6}\s+|>\s?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)"#, ""),
                                    (#"<[^>\n]*>"#, ""), (#"[*_~`]"#, ""), (#"\s+"#, " ")] {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// A JavaScript string literal for `s`.
    private static func jsString(_ s: String) -> String {
        (try? JSONEncoder().encode(s)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    private func contentIndent(of line: String) -> Int {
        let m = line.range(of: #"^\s{0,3}(?:#{1,6}\s+|>\s?|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)?"#, options: .regularExpression)
        return m.map { line.utf16.distance(from: line.startIndex, to: $0.upperBound) } ?? 0
    }

    private func lineNumber(at offset: Int) -> Int {
        textView.string.utf16.prefix(offset).reduce(0) { $1 == 10 ? $0 + 1 : $0 }
    }

    private func offset(ofLine target: Int) -> Int {
        let ns = textView.string as NSString
        var loc = 0, line = 0
        while line < target, loc < ns.length { loc = NSMaxRange(ns.lineRange(for: NSRange(location: loc, length: 0))); line += 1 }
        return loc
    }

    func textDidChange(_ notification: Notification) {
        textDocument?.text = textView.string
        colorizer.refresh(after: 0.05)
        if previewItem.isCollapsed { previewStale = true } else { scheduleRender(delay: 0.12) }
    }

    // The editor's typing goes through the document's undo manager, which is
    // how the document learns it has unsaved changes (and gets autosaved).
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { document?.undoManager }

    private func reloadFromDocument() {
        guard let doc = textDocument else { return }
        if textView.string != doc.text {
            textView.setText(doc.text)
            textView.undoManager?.removeAllActions()
        }
        applyKind()
        scheduleRender(delay: 0)
    }

    /// Keeps the preview roughly aligned with the editor while you scroll it.
    @objc private func editorScrolled() {
        guard isMarkdown, !editorItem.isCollapsed, !previewItem.isCollapsed, !suppressScrollSync,
              let doc = editorScroll.documentView else { return }
        let range = doc.frame.height - editorScroll.contentView.bounds.height
        guard range > 0 else { return }
        let fraction = min(max(editorScroll.contentView.bounds.minY / range, 0), 1)
        webView.evaluateJavaScript("window.scrollTo(0, \(fraction) * (document.documentElement.scrollHeight - innerHeight))")
    }

    // MARK: - Rendering

    private func scheduleRender(delay: TimeInterval) {
        renderWork?.cancel()
        guard let doc = textDocument else { return }
        previewStale = false
        let text = doc.text, kind = doc.kind, name = doc.displayName ?? ""
        let baseDir = doc.fileURL?.deletingLastPathComponent()
        let work = DispatchWorkItem { [weak self] in
            let body: String
            switch kind {
            case .markdown: body = Self.renderMarkdown(text, baseDir: baseDir)
            case .code(let language): body = CodeView.body(code: text, fileName: name, language: language)
            }
            DispatchQueue.main.async { self?.show(body: body, layout: kind.isMarkdown ? .markdown : .code) }
        }
        renderWork = work
        Self.renderQueue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func renderMarkdown(_ text: String, baseDir: URL?) -> String {
        let renderer = MarkdownRenderer()
        renderer.annotateLines = true
        // Local images are inlined as data URIs so they show regardless of where the page is loaded from.
        renderer.imageResolver = { src in
            guard let baseDir, !src.contains("://"), !src.hasPrefix("data:") else { return nil }
            let path = (src.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? src).removingPercentEncoding ?? src
            let file = path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseDir.appendingPathComponent(path)
            guard let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
            if let (date, uri) = imageCache[file.path], date == modified { return uri }
            guard let data = try? Data(contentsOf: file), data.count < 25_000_000 else { return nil }
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "image/png"
            let uri = "data:\(mime);base64,\(data.base64EncodedString())"
            if imageCache.count > 64 { imageCache.removeAll() } // keep memory bounded
            imageCache[file.path] = (modified, uri)
            return uri
        }
        return renderer.render(text)
    }

    private func show(body: String, layout: Page.Layout) {
        if pageLoaded, layout != pageLayout { pageLoaded = false; pendingBody = nil } // e.g. renamed .md → .py
        guard pageLoaded else {
            if pendingBody == nil {
                pageLayout = layout
                webView.loadHTMLString(Page.html(body: body, title: textDocument?.displayName ?? "", layout: layout),
                                       baseURL: textDocument?.fileURL)
            }
            pendingBody = body
            return
        }
        webView.evaluateJavaScript("document.querySelector('article').innerHTML = \(Self.jsString(body))")
        if let h = highlighted { highlight(h.start, h.end, scroll: false) } // re-render dropped the highlight
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let latest = pendingBody
        pageLoaded = true
        updateSelectionSync()
        pendingBody = nil
        if let latest { show(body: latest, layout: pageLayout) } // catch up on edits made while the page loaded
    }

    /// Links open in the browser; links to other Markdown files open here; `#anchors` scroll in place.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard action.navigationType == .linkActivated, let url = action.request.url else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
        if let fragment = url.fragment, url.isFileURL, url.path == textDocument?.fileURL?.path || url.path.isEmpty {
            let id = Self.jsString(fragment.removingPercentEncoding ?? fragment)
            webView.evaluateJavaScript("document.getElementById(\(id))?.scrollIntoView({behavior: 'smooth'})")
        } else if url.isFileURL, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: UTType("net.daringfireball.markdown")!) {
            NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func printOperation(printInfo: NSPrintInfo) -> NSPrintOperation {
        let op = webView.printOperation(with: printInfo)
        op.view?.frame = webView.bounds
        return op
    }

    // MARK: - Actions

    @objc func toggleEditor(_ sender: Any?) {
        guard let window else { return }
        if !isMarkdown { return toggleCodeEditor(in: window) }
        if editorItem.isCollapsed { showEditor(in: window) } else { hideEditor(in: window) }
    }

    /// Code: the editor replaces the read-only view (both would show the same thing).
    private func toggleCodeEditor(in window: NSWindow) {
        let editing = editorItem.isCollapsed
        editorItem.isCollapsed = !editing
        previewItem.isCollapsed = editing
        if !editing, previewStale { scheduleRender(delay: 0) }
        window.makeFirstResponder(editing ? textView : webView)
        updateSelectionSync()
    }

    /// Splits the window in half, first growing it to at least 1600×1000 (or the screen) so both panels fit.
    private func showEditor(in window: NSWindow) {
        let minimum = NSSize(width: 1600, height: 1000)
        let current = window.frame
        if current.width < minimum.width || current.height < minimum.height,
           !window.styleMask.contains(.fullScreen), let screen = window.screen?.visibleFrame {
            var frame = current
            frame.size.width = min(max(current.width, minimum.width), screen.width)
            frame.size.height = min(max(current.height, minimum.height), screen.height)
            // Grow evenly around the current window, then keep it on screen.
            frame.origin.x -= (frame.width - current.width) / 2
            frame.origin.y -= (frame.height - current.height) / 2
            frame.origin.x = min(max(frame.origin.x, screen.minX), screen.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, screen.minY), screen.maxY - frame.height)
            frameBeforeEditing = current
            window.setFrame(frame, display: true, animate: true)
            expandedFrame = window.frame
        }
        editorItem.isCollapsed = false
        previewItem.isCollapsed = false
        if previewStale { scheduleRender(delay: 0) }
        splitController.splitView.setPosition(splitController.splitView.bounds.width / 2, ofDividerAt: 0)
        window.makeFirstResponder(textView)
        updateSelectionSync()
        textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification)) // highlight the cursor's block
    }

    private func hideEditor(in window: NSWindow) {
        previewItem.isCollapsed = false
        editorItem.isCollapsed = true
        highlighted = nil
        updateSelectionSync()
        // Shrink back only if the user hasn't moved or resized the window since we widened it.
        if let before = frameBeforeEditing, window.frame == expandedFrame {
            window.setFrame(before, display: true, animate: true)
        }
        frameBeforeEditing = nil
        expandedFrame = nil
        window.makeFirstResponder(webView)
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(webView.pageZoom * 1.1) }
    @objc func zoomOut(_ sender: Any?) { setZoom(webView.pageZoom / 1.1) }
    @objc func resetZoom(_ sender: Any?) { setZoom(1) }

    private func setZoom(_ zoom: CGFloat) {
        webView.pageZoom = min(max(zoom, 0.5), 3)
        textView.fontSize = 13 * webView.pageZoom
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(toggleEditor(_:)) { item.title = editorItem.isCollapsed ? "Show Editor" : "Hide Editor" }
        return true
    }

    // MARK: - Toolbar

    private static let editItem = NSToolbarItem.Identifier("edit")

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.editItem] }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { [.flexibleSpace, Self.editItem] }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard id == Self.editItem else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = "Edit"
        item.toolTip = "Show or hide the editor (⌘E)"
        item.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "Edit")
        item.isBordered = true
        item.target = self
        item.action = #selector(toggleEditor(_:))
        return item
    }
}
