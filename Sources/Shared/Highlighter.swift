import Foundation

/// A small regex-based syntax highlighter. It isn't a parser: it colours
/// comments, strings, numbers, keywords, declarations and calls, which is
/// enough to make code readable at a glance. Languages live in Language.swift.
enum Highlighter {
    struct Token {
        let range: NSRange // UTF-16 range in the source
        let kind: TokenKind
    }

    /// Above this size, files are shown without colours to keep previews fast.
    static let maxHighlightedLength = 1_000_000

    static func tokens(_ code: String, language: Language) -> [Token] {
        let ns = code as NSString
        guard ns.length <= maxHighlightedLength else { return [] }
        var out: [Token] = []
        for m in language.regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            guard let group = (1..<m.numberOfRanges).first(where: { m.range(at: $0).location != NSNotFound }) else { continue }
            switch language.rules[group - 1].1 {
            case .token(let kind):
                out.append(Token(range: m.range, kind: kind))
            case .word, .call:
                let word = ns.substring(with: m.range)
                let key = language.caseInsensitive ? word.lowercased() : word
                let kind: TokenKind?
                if language.keywords.contains(key) || language.types.contains(key) { kind = .keyword }
                else if language.constants.contains(key) { kind = .constant }
                else if case .call = language.rules[group - 1].1 { kind = .entity }
                else { kind = nil }
                if let kind { out.append(Token(range: m.range, kind: kind)) }
            }
        }
        return out
    }

    /// Highlighted HTML for a Markdown code block (`lang` is the fence's info string).
    static func highlight(_ code: String, lang: String) -> String {
        guard let language = Language.named(lang) else { return escapeHTML(code) }
        return htmlLines(code, language: language).joined(separator: "\n")
    }

    /// Highlighted HTML split into lines; spans that cross a newline are closed and reopened.
    static func htmlLines(_ code: String, language: Language?) -> [String] {
        let ns = code as NSString
        var lines = [""]
        func emit(_ range: NSRange, _ kind: TokenKind?) {
            guard range.length > 0 else { return }
            for (i, part) in ns.substring(with: range).components(separatedBy: "\n").enumerated() {
                if i > 0 { lines.append("") }
                guard !part.isEmpty else { continue }
                lines[lines.count - 1] += kind.map { "<span class=\"\($0.cssClass)\">\(escapeHTML(part))</span>" } ?? escapeHTML(part)
            }
        }
        var last = 0
        for token in language.map({ tokens(code, language: $0) }) ?? [] {
            emit(NSRange(location: last, length: token.range.location - last), nil)
            emit(token.range, token.kind)
            last = NSMaxRange(token.range)
        }
        emit(NSRange(location: last, length: ns.length - last), nil)
        return lines
    }
}
