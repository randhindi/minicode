import AppKit

/// The editor: a plain-text view on a TextKit 1 stack (for line numbers and
/// temporary colouring), with auto-indent and code-friendly defaults.
final class CodeTextView: NSTextView {
    static func make() -> (NSScrollView, CodeTextView) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = CodeTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        return (scroll, textView)
    }

    var fontSize: CGFloat = 13 { didSet { applyFont() } }

    /// Code scrolls horizontally; prose (Markdown, plain text) wraps.
    var wrapsLines = true {
        didSet {
            guard let container = textContainer, let scroll = enclosingScrollView else { return }
            isHorizontallyResizable = !wrapsLines
            container.widthTracksTextView = wrapsLines
            container.containerSize = NSSize(width: wrapsLines ? scroll.contentSize.width : CGFloat.greatestFiniteMagnitude,
                                             height: CGFloat.greatestFiniteMagnitude)
            scroll.hasHorizontalScroller = !wrapsLines
            if wrapsLines { frame.size.width = scroll.contentSize.width }
        }
    }

    func configure() {
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        smartInsertDeleteEnabled = false
        textContainerInset = NSSize(width: 10, height: 14)
        textColor = .textColor
        backgroundColor = .textBackgroundColor
        applyFont()
    }

    /// Replaces the whole text, keeping the editor's font and tab stops.
    func setText(_ text: String) {
        string = text
        textStorage?.setAttributes(typingAttributes, range: NSRange(location: 0, length: (string as NSString).length))
    }

    private func applyFont() {
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = 4 * (" " as NSString).size(withAttributes: [.font: font]).width
        paragraph.tabStops = []
        self.font = font
        defaultParagraphStyle = paragraph
        typingAttributes = [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
        textStorage?.addAttributes([.font: font, .paragraphStyle: paragraph],
                                   range: NSRange(location: 0, length: (string as NSString).length))
        enclosingScrollView?.verticalRulerView?.needsDisplay = true
    }

    /// New lines keep the previous line's indentation.
    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let line = ns.substring(with: ns.lineRange(for: NSRange(location: selectedRange().location, length: 0)))
        let indent = String(line.prefix { $0 == " " || $0 == "\t" })
        super.insertNewline(sender)
        if !indent.isEmpty { insertText(indent, replacementRange: selectedRange()) }
    }
}

/// Colours the editor's text by language. Tokenising runs in the background;
/// colours are layout-manager temporary attributes, so they never touch the
/// document's contents or its undo history.
final class SyntaxColorizer {
    private weak var textView: NSTextView?
    private var generation = 0
    private static let queue = DispatchQueue(label: "syntax-colorizer", qos: .userInitiated)

    var language: Language? { didSet { refresh(after: 0) } }

    init(textView: NSTextView) { self.textView = textView }

    func refresh(after delay: TimeInterval) {
        generation += 1
        let current = generation
        guard let textView else { return }
        let text = textView.string
        let language = self.language
        Self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            let tokens = language.map { Highlighter.tokens(text, language: $0) } ?? []
            DispatchQueue.main.async {
                guard let self, self.generation == current, let textView = self.textView,
                      let layout = textView.layoutManager, textView.string == text else { return }
                let length = (text as NSString).length
                layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: length))
                for token in tokens where NSMaxRange(token.range) <= length {
                    layout.addTemporaryAttribute(.foregroundColor, value: token.kind.editorColor, forCharacterRange: token.range)
                }
            }
        }
    }
}

extension TokenKind {
    /// GitHub's light and dark syntax colours, matching the preview.
    var editorColor: NSColor {
        switch self {
        case .comment, .quote: return .dynamic(0x59636E, 0x9198A1)
        case .keyword: return .dynamic(0xCF222E, 0xFF7B72)
        case .string, .code: return .dynamic(0x0A3069, 0xA5D6FF)
        case .constant, .heading: return .dynamic(0x0550AE, 0x79C0FF)
        case .entity, .attribute, .emphasis: return .dynamic(0x6639BA, 0xD2A8FF)
        case .variable, .listMarker: return .dynamic(0x953800, 0xFFA657)
        case .tag: return .dynamic(0x0550AE, 0x7EE787)
        case .link: return .dynamic(0x0969DA, 0x4493F8)
        case .inserted: return .dynamic(0x116329, 0x7EE787)
        case .deleted: return .dynamic(0x82071E, 0xFFA198)
        }
    }
}

extension NSColor {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        func rgb(_ hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? rgb(dark) : rgb(light)
        }
    }
}

/// Line numbers beside the editor.
final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        if let clip = textView.enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: clip)
        }
    }

    required init(coder: NSCoder) { fatalError() }

    @objc func refresh() {
        let lines = (textView?.string ?? "").reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        let digits = max(String(lines).count, 2)
        let thickness = CGFloat(digits) * 7.5 + 20
        if abs(ruleThickness - thickness) > 0.5 { ruleThickness = thickness }
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()

        let ns = textView.string as NSString
        let font = NSFont.monospacedDigitSystemFont(ofSize: max(9, (textView.font?.pointSize ?? 13) - 2), weight: .regular)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.tertiaryLabelColor]
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)

        var line = ns.substring(to: chars.location).reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        var index = chars.location
        func draw(_ number: Int, atY y: CGFloat, height: CGFloat) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attrs)
            let point = convert(NSPoint(x: 0, y: y), from: textView)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: point.y + (height - size.height) / 2), withAttributes: attrs)
        }
        while index < NSMaxRange(chars) {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            let fragment = layout.lineFragmentRect(forGlyphAt: layout.glyphIndexForCharacter(at: lineRange.location), effectiveRange: nil)
            draw(line, atY: fragment.minY + textView.textContainerOrigin.y, height: fragment.height)
            line += 1
            index = NSMaxRange(lineRange)
        }
        // The empty last line after a trailing newline (or of an empty document).
        let extra = layout.extraLineFragmentRect
        if !extra.isEmpty, visible.intersects(extra.offsetBy(dx: 0, dy: textView.textContainerOrigin.y)) {
            draw(line, atY: extra.minY + textView.textContainerOrigin.y, height: extra.height)
        }
    }
}
