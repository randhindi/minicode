import Foundation

/// How a file is presented: rendered as Markdown, or shown as (possibly highlighted) code.
enum FileKind {
    case markdown
    case code(Language?) // nil: plain text

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdtxt", "mdtext", "mdx"]

    static func of(fileName: String, text: String) -> FileKind {
        if markdownExtensions.contains((fileName as NSString).pathExtension.lowercased()) { return .markdown }
        let firstLine = text.prefix(200).split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
        return .code(Language.detect(fileName: fileName, firstLine: firstLine))
    }

    var isMarkdown: Bool { if case .markdown = self { return true } else { return false } }

    var language: Language? {
        switch self {
        case .markdown: return .markdown
        case .code(let language): return language
        }
    }

    /// Decodes file contents as text, or returns nil for binary data (e.g. a `.ts` video).
    static func decodeText(_ data: Data) -> String? {
        if data.prefix(8192).contains(0) { return nil }
        if let text = String(data: data, encoding: .utf8) { return text }
        let lossy = String(decoding: data, as: UTF8.self)
        let replaced = lossy.prefix(8192).filter { $0 == "\u{FFFD}" }.count
        return replaced < 16 ? lossy : String(data: data, encoding: .isoLatin1)
    }
}

/// The full preview page for a file, as Quick Look shows it.
enum Preview {
    static func html(fileName: String, text: String, imageResolver: ((String) -> String?)? = nil) -> String {
        switch FileKind.of(fileName: fileName, text: text) {
        case .markdown:
            let renderer = MarkdownRenderer()
            renderer.imageResolver = imageResolver
            return Page.html(body: renderer.render(text), title: fileName)
        case .code(let language):
            return CodeView.page(code: text, fileName: fileName, language: language)
        }
    }
}
