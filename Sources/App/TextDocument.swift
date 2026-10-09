import AppKit

/// A Markdown, source-code or plain-text file. Markdown is rendered; everything
/// else is shown as highlighted code.
@objc(TextDocument)
final class TextDocument: NSDocument {
    /// The document's source. The editor writes here as you type.
    var text = ""
    /// Called when `text` is replaced from disk (open, revert, or an external edit).
    var onReload: (() -> Void)?

    override class var autosavesInPlace: Bool { true }

    // A rename can change the kind (say .txt → .py), so refresh the window.
    override var fileURL: URL? {
        didSet { if oldValue != fileURL { DispatchQueue.main.async { self.onReload?() } } }
    }

    /// Untitled documents are Markdown; files are judged by name (and `#!` line).
    var kind: FileKind {
        guard let name = fileURL?.lastPathComponent else { return .markdown }
        return FileKind.of(fileName: name, text: text)
    }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self, startEditing: fileURL == nil))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let decoded = FileKind.decodeText(data) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSLocalizedFailureReasonErrorKey: "This isn't a text file."])
        }
        text = decoded
        DispatchQueue.main.async { self.onReload?() }
    }

    override func data(ofType typeName: String) throws -> Data {
        Data(text.utf8)
    }

    override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey: Any]) throws -> NSPrintOperation {
        guard let controller = windowControllers.first as? DocumentWindowController else { throw CocoaError(.featureUnsupported) }
        return controller.printOperation(printInfo: printInfo)
    }
}
