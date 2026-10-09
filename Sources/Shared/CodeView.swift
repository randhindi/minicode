import Foundation

/// Renders a source file the way GitHub shows one: a header with file facts,
/// then line-numbered, highlighted code.
enum CodeView {
    /// Above this size only the beginning of the file is shown.
    static let maxShownLength = 4_000_000

    static func page(code source: String, fileName: String, language: Language?) -> String {
        Page.html(body: body(code: source, fileName: fileName, language: language), title: fileName, layout: .code)
    }

    static func body(code source: String, fileName: String, language: Language?) -> String {
        var code = source.replacingOccurrences(of: "\r\n", with: "\n")
        let byteCount = code.utf8.count
        var truncated = false
        if (code as NSString).length > maxShownLength {
            let cut = (code as NSString).substring(to: maxShownLength)
            code = cut.range(of: "\n", options: .backwards).map { String(cut[..<$0.lowerBound]) } ?? cut
            truncated = true
        }

        var lines = Highlighter.htmlLines(code, language: language)
        if lines.count > 1, lines.last == "" { lines.removeLast() } // a trailing newline isn't a line
        let total = truncated ? source.components(separatedBy: "\n").count : lines.count

        var facts = ["\(total) line\(total == 1 ? "" : "s")", formatBytes(byteCount), language?.name ?? "Plain Text"]
        if truncated { facts.append("showing the first \(lines.count) lines") }
        if language != nil, (code as NSString).length > Highlighter.maxHighlightedLength { facts.append("too large to highlight") }

        var html = """
        <div class="code-file">
        <div class="code-header"><span class="code-name">\(escapeHTML(fileName))</span><span class="code-facts">\(facts.map(escapeHTML).joined(separator: " · "))</span></div>
        <div class="code-scroll"><table class="code\(language == nil ? " wrap" : "")"><tbody>

        """
        html.reserveCapacity(code.utf8.count * 2)
        for (i, line) in lines.enumerated() {
            html += "<tr><td class=\"ln\" data-n=\"\(i + 1)\"></td><td class=\"lc\">\(line.isEmpty ? "\n" : line)</td></tr>\n"
        }
        return html + "</tbody></table></div>\n</div>\n"
    }

    private static func formatBytes(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}
