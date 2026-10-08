import AppKit

@objc(MarkdownDocument)
final class MarkdownDocument: NSDocument {
    /// The document's source. The editor writes here as you type.
    var text = ""
    /// Called when `text` is replaced from disk (open, revert, or an external edit).
    var onReload: (() -> Void)?

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self, startEditing: fileURL == nil))
    }

    override func read(from data: Data, ofType typeName: String) throws {
        text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
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
