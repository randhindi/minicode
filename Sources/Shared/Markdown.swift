import Foundation

/// A small, dependency-free Markdown → HTML renderer covering CommonMark
/// essentials plus the GitHub extensions people actually use: tables, task
/// lists, strikethrough, autolinks, fenced code and `> [!NOTE]` alerts.
final class MarkdownRenderer {
    /// Called with each image `src`; return a replacement (e.g. `cid:` URL) or nil to keep it.
    var imageResolver: ((String) -> String?)?
    /// Adds `data-line`/`data-end` (0-based source lines, end exclusive) to rendered blocks.
    var annotateLines = false

    private var refs: [String: (url: String, title: String?)] = [:]
    private var slugs: [String: Int] = [:]
    private var tokens: [String] = []

    func render(_ source: String) -> String {
        refs = [:]; slugs = [:]; tokens = []
        var text = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var lines = text.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\t", with: "    ") }
        lines = stripFrontMatter(lines)
        lines = collectReferences(lines)
        return blocks(lines[...], tight: false)
    }

    // MARK: - Pre-passes

    private func stripFrontMatter(_ lines: [String]) -> [String] {
        guard lines.first == "---", let close = lines.dropFirst().firstIndex(where: { $0 == "---" || $0 == "..." }),
              lines[1..<close].contains(where: { $0.contains(":") }) else { return lines }
        return Array(repeating: "", count: close + 1) + lines[(close + 1)...] // blanked, so line numbers still match the source
    }

    private func collectReferences(_ lines: [String]) -> [String] {
        var out: [String] = []
        var fence: String?
        for line in lines {
            if let g = R.fence.groups(line) {
                if fence == nil { fence = g[2] } else if line.trimmingCharacters(in: .whitespaces).hasPrefix(fence!) { fence = nil }
            } else if fence == nil, let g = R.refDef.groups(line) {
                refs[normalizeLabel(g[1])] = (g[2], g[3].isEmpty ? nil : g[3])
                out.append("") // keep line numbers aligned with the source
                continue
            }
            out.append(line)
        }
        return out
    }

    private func normalizeLabel(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Blocks

    /// `base + index` is the source line of `lines[index]`.
    private func blocks(_ lines: ArraySlice<String>, tight: Bool, base: Int = 0) -> String {
        var out: [String] = []
        var i = lines.startIndex
        let end = lines.endIndex

        // Each iteration emits at most one block; it is tagged with its line range once the next one starts.
        var pending: (index: Int, start: Int)?
        func flush(_ stop: Int) {
            guard annotateLines, let p = pending, p.index < out.count else { pending = nil; return }
            var e = stop
            while e > p.start + 1, isBlank(lines[e - 1]) { e -= 1 }
            out[p.index] = mark(out[p.index], base + p.start, base + e)
            pending = nil
        }

        while i < end {
            let line = lines[i]
            if isBlank(line) { i += 1; continue }
            flush(i)
            pending = (out.count, i)

            // Indented code
            if indent(line) >= 4 {
                var body: [String] = []
                var j = i
                while j < end, isBlank(lines[j]) || indent(lines[j]) >= 4 { body.append(dropIndent(lines[j], 4)); j += 1 }
                while let last = body.last, isBlank(last) { body.removeLast() }
                out.append(codeBlock(body.joined(separator: "\n"), lang: ""))
                i = j; continue
            }

            // Fenced code
            if let g = R.fence.groups(line) {
                let ind = g[1].count, marker = g[2], lang = g[3]
                var body: [String] = []
                var j = i + 1
                while j < end {
                    let t = lines[j].trimmingCharacters(in: .whitespaces)
                    if indent(lines[j]) < 4, t.hasPrefix(marker), t.allSatisfy({ $0 == marker.first }) { break }
                    body.append(dropIndent(lines[j], ind)); j += 1
                }
                out.append(codeBlock(body.joined(separator: "\n"), lang: lang))
                i = min(j + 1, end); continue
            }

            if let g = R.atx.groups(line) {
                out.append(heading(g[1].count, g[2])); i += 1; continue
            }

            if R.hr.matches(line) { out.append("<hr>"); i += 1; continue }

            // Blockquote (and GitHub alerts)
            if R.quote.matches(line) {
                var inner: [String] = []
                var j = i
                while j < end {
                    if let g = R.quote.groups(lines[j]) { inner.append(g[1]) }
                    else if !isBlank(lines[j]), !startsBlock(lines[j]), let last = inner.last, !isBlank(last) { inner.append(lines[j]) }
                    else { break }
                    j += 1
                }
                if let first = inner.first, let g = R.alert.groups(first) {
                    let kind = g[1].lowercased()
                    let icon = "<svg class=\"octicon\" viewBox=\"0 0 16 16\" width=\"16\" height=\"16\" aria-hidden=\"true\"><path d=\"\(Page.alertIcons[kind] ?? "")\"></path></svg>"
                    out.append("<div class=\"markdown-alert markdown-alert-\(kind)\"><p class=\"markdown-alert-title\">\(icon)\(kind.capitalized)</p>\n\(blocks(inner.dropFirst(), tight: false, base: base + i))</div>")
                } else {
                    out.append("<blockquote>\n\(blocks(inner[...], tight: false, base: base + i))</blockquote>")
                }
                i = j; continue
            }

            if let m = listMarker(line) {
                let (html, next) = list(lines, from: i, first: m, base: base)
                out.append(html); i = next; continue
            }

            // Table
            if i + 1 < end, line.contains("|"), R.tableDelim.matches(lines[i + 1]) {
                let header = splitRow(line)
                let aligns = splitRow(lines[i + 1]).map { cell -> String in
                    switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
                    case (true, true): return " style=\"text-align:center\""
                    case (false, true): return " style=\"text-align:right\""
                    case (true, false): return " style=\"text-align:left\""
                    default: return ""
                    }
                }
                if header.count == aligns.count {
                    var j = i + 2
                    var html = "<table>\n<thead><tr\(lineAttrs(base + i, base + i + 1))>"
                    for (k, cell) in header.enumerated() { html += "<th\(aligns[k])>\(inline(cell))</th>" }
                    html += "</tr></thead>\n<tbody>\n"
                    while j < end, !isBlank(lines[j]), !startsBlock(lines[j]) {
                        let cells = splitRow(lines[j])
                        html += "<tr\(lineAttrs(base + j, base + j + 1))>"
                        for k in 0..<header.count { html += "<td\(aligns[k])>\(k < cells.count ? inline(cells[k]) : "")</td>" }
                        html += "</tr>\n"
                        j += 1
                    }
                    out.append(html + "</tbody>\n</table>")
                    i = j; continue
                }
            }

            // $$ display math $$
            if let g = R.mathBlock.groups(line) {
                var tex: String
                var j = i + 1
                if let close = g[1].range(of: "$$", options: .backwards) {
                    tex = String(g[1][..<close.lowerBound])
                } else {
                    var body = [g[1]]
                    while j < end {
                        let l = lines[j]; j += 1
                        if let close = l.range(of: "$$") { body.append(String(l[..<close.lowerBound])); break }
                        body.append(l)
                    }
                    tex = body.joined(separator: "\n")
                }
                out.append(MathRenderer.html(tex.trimmingCharacters(in: .whitespacesAndNewlines), display: true))
                i = j; continue
            }

            // Raw HTML block
            if R.htmlBlock.matches(line) {
                var body: [String] = []
                var j = i
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("<!--") {
                    while j < end { body.append(lines[j]); j += 1; if body.last!.contains("-->") { break } }
                } else {
                    while j < end, !isBlank(lines[j]) { body.append(lines[j]); j += 1 }
                }
                out.append(rawHTML(body.joined(separator: "\n")))
                i = j; continue
            }

            // Paragraph (or setext heading)
            var para = [line]
            var setext = 0
            var j = i + 1
            while j < end, !isBlank(lines[j]) {
                let l = lines[j]
                if indent(l) < 4, let g = R.setext.groups(l) { setext = g[1].hasPrefix("=") ? 1 : 2; j += 1; break }
                if startsBlock(l) { break }
                if l.contains("|"), j + 1 < end, R.tableDelim.matches(lines[j + 1]) { break }
                para.append(l); j += 1
            }
            i = j
            let text = para.map { String($0.drop(while: { $0 == " " })) }.joined(separator: "\n")
                .replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
            if setext > 0 { out.append(heading(setext, text)) }
            else if tight { out.append(inline(text)) }
            else { out.append("<p>\(inline(text))</p>") }
        }
        flush(end)
        return out.joined(separator: "\n") + (out.isEmpty ? "" : "\n")
    }

    private func lineAttrs(_ start: Int, _ end: Int) -> String {
        annotateLines ? " data-line=\"\(start)\" data-end=\"\(end)\"" : ""
    }

    private func mark(_ html: String, _ start: Int, _ end: Int) -> String {
        guard let g = R.firstTag.groups(html) else { return html }
        return g[1] + " data-line=\"\(start)\" data-end=\"\(end)\"" + html.dropFirst(g[1].count)
    }

    private func startsBlock(_ l: String) -> Bool {
        if indent(l) >= 4 { return false }
        if R.fence.matches(l) || R.mathBlock.matches(l) || R.atx.matches(l) || R.hr.matches(l) || R.quote.matches(l) { return true }
        if let m = listMarker(l), !m.content.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        return false
    }

    // MARK: - Lists

    private struct ListMarker {
        let indent: Int, ordered: Bool, start: Int, delim: Character, contentIndent: Int, content: String
    }

    private func listMarker(_ l: String) -> ListMarker? {
        guard let g = R.list.groups(l) else { return nil }
        let ind = g[1].count, marker = g[2], spaces = g[4].count
        var content = g[5], pad = spaces
        if spaces > 4 { pad = 1; content = String(repeating: " ", count: spaces - 1) + content }
        if spaces == 0 { pad = 1 }
        return ListMarker(indent: ind, ordered: !g[3].isEmpty, start: Int(g[3]) ?? 1, delim: marker.last!,
                          contentIndent: ind + marker.count + pad, content: content)
    }

    private func list(_ lines: ArraySlice<String>, from start: Int, first: ListMarker, base: Int) -> (String, Int) {
        var items: [(lines: [String], task: Bool?, start: Int)] = []
        var loose = false
        var j = start
        let end = lines.endIndex
        func sibling(_ l: String) -> ListMarker? {
            guard let m = listMarker(l), m.ordered == first.ordered, m.delim == first.delim, !R.hr.matches(l) else { return nil }
            return m
        }

        while j < end, let m = sibling(lines[j]) {
            let itemStart = base + j
            var item = [m.content]
            j += 1
            while j < end {
                let l = lines[j]
                if isBlank(l) { item.append(""); j += 1; continue }
                let ind = indent(l)
                if ind >= m.contentIndent || (ind >= m.indent + 2 && listMarker(l) != nil) {
                    item.append(dropIndent(l, m.contentIndent)); j += 1; continue
                }
                if item.last == "" || listMarker(l) != nil || startsBlock(l) { break }
                item.append(l); j += 1 // lazy continuation
            }
            var trailing = 0
            while item.last == "" { item.removeLast(); trailing += 1 }
            if trailing > 0, j < end, sibling(lines[j]) != nil { loose = true }
            for k in item.indices where item[k] == "" && k + 1 < item.count {
                let next = item[k + 1]
                if indent(next) == 0, !next.isEmpty, listMarker(next) == nil { loose = true }
            }
            var task: Bool?
            if let g = R.task.groups(item[0]) { task = g[1] != " "; item[0] = g[2] }
            items.append((item, task, itemStart))
        }

        let tag = first.ordered ? "ol" : "ul"
        var html = "<\(tag)"
        if first.ordered, first.start != 1 { html += " start=\"\(first.start)\"" }
        if items.contains(where: { $0.task != nil }) { html += " class=\"contains-task-list\"" }
        html += ">\n"
        for item in items {
            let body = blocks(item.lines[...], tight: !loose, base: item.start).trimmingCharacters(in: .newlines)
            let attrs = lineAttrs(item.start, item.start + item.lines.count)
            if let checked = item.task {
                html += "<li\(attrs) class=\"task-list-item\"><input type=\"checkbox\" class=\"task-list-item-checkbox\" disabled\(checked ? " checked" : "")> \(body)</li>\n"
            } else {
                html += "<li\(attrs)>\(body)</li>\n"
            }
        }
        return (html + "</\(tag)>", j)
    }

    // MARK: - Block helpers

    private func heading(_ level: Int, _ raw: String) -> String {
        let base = raw.lowercased().unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "_" }
            .map(String.init).joined().replacingOccurrences(of: " ", with: "-")
        var slug = base
        if let n = slugs[base] { slug = "\(base)-\(n)"; slugs[base] = n + 1 } else { slugs[base] = 1 }
        return "<h\(level) id=\"\(slug)\">\(inline(raw))</h\(level)>"
    }

    private func codeBlock(_ code: String, lang: String) -> String {
        let l = lang.lowercased()
        if l == "math" { return MathRenderer.html(code, display: true) }
        // Not GitHub behaviour, but people often fence formulas as latex/tex: render them if they parse.
        if l == "latex" || l == "tex" || l == "katex", let math = MathRenderer.tryHTML(code, display: true, strict: true) { return math }
        let cls = l.isEmpty ? "" : " class=\"language-\(escapeAttr(l))\""
        return "<pre><code\(cls)>\(Highlighter.highlight(code, lang: l))</code></pre>"
    }

    private func splitRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|"), !s.hasSuffix("\\|") { s.removeLast() }
        var cells: [String] = [], cur = "", inCode = false, prev: Character = " "
        for c in s {
            if c == "`" { inCode.toggle() }
            if c == "|", prev != "\\", !inCode { cells.append(cur); cur = "" } else { cur.append(c) }
            prev = c
        }
        cells.append(cur)
        return cells.map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\\|", with: "|") }
    }

    private func rawHTML(_ html: String) -> String {
        guard let resolve = imageResolver else { return html }
        return R.imgSrc.replace(html) { g in g[1] + g[2] + (resolve(g[3]) ?? g[3]) + g[2] }
    }

    // MARK: - Inline

    private func stash(_ html: String) -> String {
        tokens.append(html)
        return "\u{E000}\(tokens.count - 1)\u{E001}"
    }

    private func inline(_ text: String) -> String {
        var s = text
        s = R.mathTick.replace(s) { g in self.stash(MathRenderer.html(g[1], display: false)) }
        s = R.codeSpan.replace(s) { g in
            var c = g[2].replacingOccurrences(of: "\n", with: " ")
            if c.count > 2, c.hasPrefix(" "), c.hasSuffix(" "), c.contains(where: { $0 != " " }) { c = String(c.dropFirst().dropLast()) }
            return self.stash("<code>\(escapeHTML(c))</code>")
        }
        s = R.mathDisplayInline.replace(s) { g in self.stash(MathRenderer.html(g[1].trimmingCharacters(in: .whitespacesAndNewlines), display: true)) }
        s = R.mathInline.replace(s) { g in self.stash(MathRenderer.html(g[1], display: false)) }
        s = R.hardBreak.replace(s) { _ in self.stash("<br>") + "\n" }
        s = R.escape.replace(s) { g in self.stash(escapeHTML(g[1])) }
        s = R.autolink.replace(s) { g in
            let href = g[1].contains("://") ? g[1] : "mailto:" + g[1]
            return self.stash("<a href=\"\(escapeAttr(href))\">\(escapeHTML(g[1]))</a>")
        }
        s = R.inlineHTML.replace(s) { g in self.stash(self.rawHTML(g[0])) }
        s = escapeText(s)

        s = R.image.replace(s) { g in self.stash(self.img(src: g[2], alt: g[1], title: g[3] + g[4])) }
        s = R.refImage.replace(s) { g in
            guard let r = self.refs[self.normalizeLabel(g[2].isEmpty ? g[1] : g[2])] else { return g[0] }
            return self.stash(self.img(src: escapeText(r.url), alt: g[1], title: r.title.map(escapeText) ?? ""))
        }
        s = R.link.replace(s) { g in self.stash(self.anchor(href: g[2], title: g[3] + g[4], text: g[1])) }
        s = R.refLink.replace(s) { g in
            let label = g[2].isEmpty ? g[1] : g[2]
            guard let r = self.refs[self.normalizeLabel(label)] else { return g[0] }
            return self.stash(self.anchor(href: escapeText(r.url), title: r.title.map(escapeText) ?? "", text: g[1]))
        }
        s = R.shortcutLink.replace(s) { g in
            guard let r = self.refs[self.normalizeLabel(g[1])] else { return g[0] }
            return self.stash(self.anchor(href: escapeText(r.url), title: r.title.map(escapeText) ?? "", text: g[1]))
        }
        s = R.bareURL.replace(s) { g in
            let href = g[0].hasPrefix("www.") ? "http://" + g[0] : g[0]
            return self.stash("<a href=\"\(href.replacingOccurrences(of: "\"", with: "&quot;"))\">\(g[0])</a>")
        }
        s = emphasis(s)
        return restore(s)
    }

    private func emphasis(_ text: String) -> String {
        var s = text
        s = R.strongEm.replace(s) { g in "<strong><em>\(g[1])</em></strong>" }
        s = R.strongStar.replace(s) { g in "<strong>\(g[1])</strong>" }
        s = R.strongUnder.replace(s) { g in "<strong>\(g[1])</strong>" }
        s = R.emStar.replace(s) { g in "<em>\(g[1])</em>" }
        s = R.emUnder.replace(s) { g in "<em>\(g[1])</em>" }
        s = R.strike.replace(s) { g in "<del>\(g[1])</del>" }
        return s
    }

    private func restore(_ text: String) -> String {
        var s = text
        for _ in 0..<8 where s.contains("\u{E000}") {
            s = R.token.replace(s) { g in self.tokens[Int(g[1])!] }
        }
        return s
    }

    private func cleanURL(_ u: String) -> String {
        var u = u
        if u.hasPrefix("&lt;"), u.hasSuffix("&gt;") { u = String(u.dropFirst(4).dropLast(4)) }
        return u.replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func anchor(href: String, title: String, text: String) -> String {
        let t = title.isEmpty ? "" : " title=\"\(title.replacingOccurrences(of: "\"", with: "&quot;"))\""
        return "<a href=\"\(cleanURL(href))\"\(t)>\(emphasis(text))</a>"
    }

    private func img(src: String, alt: String, title: String) -> String {
        var src = cleanURL(src)
        if let resolved = imageResolver?(src.replacingOccurrences(of: "&amp;", with: "&")) { src = resolved }
        let altText = restore(alt).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\"", with: "&quot;")
        let t = title.isEmpty ? "" : " title=\"\(title.replacingOccurrences(of: "\"", with: "&quot;"))\""
        return "<img src=\"\(src)\" alt=\"\(altText)\"\(t)>"
    }

    // MARK: - Line helpers

    private func isBlank(_ l: String) -> Bool { l.allSatisfy { $0 == " " } }
    private func indent(_ l: String) -> Int { l.prefix { $0 == " " }.count }
    private func dropIndent(_ l: String, _ n: Int) -> String { String(l.dropFirst(min(n, indent(l)))) }
}

// MARK: - Escaping

func escapeHTML(_ s: String) -> String {
    s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

func escapeAttr(_ s: String) -> String { escapeHTML(s).replacingOccurrences(of: "\"", with: "&quot;") }

/// Like `escapeHTML`, but leaves existing entities such as `&nbsp;` intact.
private func escapeText(_ s: String) -> String {
    R.bareAmp.replace(s) { _ in "&amp;" }.replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}

// MARK: - Regexes

private enum R {
    static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }

    static let fence = re(#"^( {0,3})(`{3,}|~{3,})[ \t]*([^\s`]*)"#)
    static let atx = re(#"^ {0,3}(#{1,6})(?:[ \t]+(.*?))?(?:[ \t]+#+)?[ \t]*$"#)
    static let hr = re(#"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$"#)
    static let setext = re(#"^ {0,3}(=+|-+)[ \t]*$"#)
    static let quote = re(#"^ {0,3}> ?(.*)$"#)
    static let alert = re(#"^\s*\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\]\s*$"#)
    static let list = re(#"^( {0,3})([-*+]|(\d{1,9})[.)])(?:( +)(.*))?$"#)
    static let task = re(#"^\[([ xX])\][ \t]+(.*)$"#)
    static let tableDelim = re(#"^ {0,3}\|?[ \t]*:?-+:?[ \t]*(?:\|[ \t]*:?-+:?[ \t]*)*\|?[ \t]*$"#)
    static let htmlBlock = re(#"^ {0,3}(?:<!--|</?[A-Za-z][A-Za-z0-9-]*(?:[\s/>]|$))"#)
    static let refDef = re(#"^ {0,3}\[([^\]^][^\]]*)\]:[ \t]*<?([^\s>]+)>?(?:[ \t]+["'(](.*)["')])?[ \t]*$"#)
    static let firstTag = re(#"^(\s*<[A-Za-z][A-Za-z0-9-]*)"#)
    static let imgSrc = re(#"(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2"#)

    // GitHub math: $$…$$ on their own lines, $…$ inline, and $`…`$.
    static let mathBlock = re(#"^ {0,3}\$\$(?!.*\$\$.*\S.*$)(.*)$"#)
    static let mathTick = re(#"\$`([^`]+)`\$"#)
    static let mathDisplayInline = re(#"(?<![\\$])\$\$((?:\\.|[^$\\])+?)\$\$"#)
    static let mathInline = re(#"(?<![\\$\w])\$(?![\s$])((?:\\.|[^$\\\n]|\n(?!\n))+?)(?<![\s\\])\$(?![\w$])"#)
    static let codeSpan = re(#"(?<!`)(`+)(?!`)([\s\S]*?[^`])\1(?!`)"#)
    static let hardBreak = re(#"(?: {2,}|\\)\n"#)
    static let escape = re(#"\\([!-/:-@\[-`{-~])"#)
    static let autolink = re(#"<((?:https?|ftp)://[^\s<>]+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+)>"#)
    static let inlineHTML = re(#"<!--[\s\S]*?-->|</?[A-Za-z][A-Za-z0-9-]*(?:\s+[A-Za-z_:][\w.:-]*(?:\s*=\s*(?:"[^"]*"|'[^']*'|[^\s"'=<>`]+))?)*\s*/?>"#)
    static let bareAmp = re(#"&(?!#?[A-Za-z0-9]+;)"#)

    private static let label = #"((?:[^\[\]]|\[[^\]]*\])*)"#
    private static let dest = #"\(\s*((?:&lt;.*?&gt;)|[^\s()]*(?:\([^\s()]*\)[^\s()]*)*)(?:\s+(?:"([^"]*)"|'([^']*)'))?\s*\)"#
    static let image = re(#"!\["# + label + #"\]"# + dest)
    static let link = re(#"\["# + label + #"\]"# + dest)
    static let refImage = re(#"!\[([^\]]*)\]\[([^\]]*)\]"#)
    static let refLink = re(#"\["# + label + #"\]\[([^\]]*)\]"#)
    static let shortcutLink = re(#"\[([^\[\]\uE000]+)\](?![\[(:])"#)
    static let bareURL = re(#"(?<![\w/"=\uE001])(?:https?://|www\.)[^\s<>\uE000]*[^\s<>\uE000.,:;!?"'*_)\]]"#)

    static let strongEm = re(#"\*\*\*(?=\S)([\s\S]+?)(?<=\S)\*\*\*"#)
    static let strongStar = re(#"\*\*(?=\S)([\s\S]+?)(?<=\S)\*\*"#)
    static let strongUnder = re(#"(?<![\w])__(?=\S)([\s\S]+?)(?<=\S)__(?![\w])"#)
    static let emStar = re(#"(?<!\*)\*(?=[^\s*])([\s\S]*?[^\s*])\*(?!\*)"#)
    static let emUnder = re(#"(?<![\w])_(?=[^\s_])([\s\S]*?[^\s_])_(?![\w])"#)
    static let strike = re(#"~~(?=\S)([\s\S]+?)(?<=\S)~~"#)
    static let token = re("\u{E000}(\\d+)\u{E001}")
}

extension NSRegularExpression {
    func matches(_ s: String) -> Bool {
        firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    /// Capture groups of the first match (unmatched groups are ""), or nil.
    func groups(_ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
    }

    func replace(_ s: String, _ transform: ([String]) -> String) -> String {
        let ns = s as NSString
        var out = "", last = 0
        for m in matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += transform((0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) })
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }
}
