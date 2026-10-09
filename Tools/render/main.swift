import Foundation

// Prints the preview page for a file (Markdown or code), exactly as the
// Quick Look extension renders it, minus image attachments.
// Usage: render <file>   (KATEX=path/to/katex.min.js enables math)
guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render <file>\n".utf8))
    exit(2)
}
let path = CommandLine.arguments[1]
if let katex = ProcessInfo.processInfo.environment["KATEX"] { MathRenderer.scriptURL = URL(fileURLWithPath: katex) }
guard let text = FileKind.decodeText(try Data(contentsOf: URL(fileURLWithPath: path))) else {
    FileHandle.standardError.write(Data("\(path): not a text file\n".utf8))
    exit(1)
}
print(Preview.html(fileName: (path as NSString).lastPathComponent, text: text))
