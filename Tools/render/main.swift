import Foundation

// Renders a Markdown file to a full HTML page on stdout, exactly as the
// Quick Look extension does (minus image attachments).
// Usage: render <file.md>   (KATEX=path/to/katex.min.js enables math)
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render <file.md>\n".utf8))
    exit(2)
}
let path = CommandLine.arguments[1]
if let katex = ProcessInfo.processInfo.environment["KATEX"] { MathRenderer.scriptURL = URL(fileURLWithPath: katex) }
let text = try String(contentsOfFile: path, encoding: .utf8)
print(Page.html(body: MarkdownRenderer().render(text), title: (path as NSString).lastPathComponent))
