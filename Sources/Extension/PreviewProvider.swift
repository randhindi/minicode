import Foundation
import QuickLookUI
import UniformTypeIdentifiers

/// Quick Look entry point: renders Markdown, or shows code with line numbers and highlighting.
@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        // `.ts` is also MPEG-2 video; anything that isn't text is left to the system.
        guard let text = FileKind.decodeText(try Data(contentsOf: url)) else { throw CocoaError(.fileReadCorruptFile) }

        // Local images in Markdown are shipped to the preview as attachments, referenced by `cid:`.
        let baseDir = url.deletingLastPathComponent()
        var attachments: [String: QLPreviewReplyAttachment] = [:]
        var resolved: [String: String] = [:]
        let html = Preview.html(fileName: url.lastPathComponent, text: text) { src in
            if let hit = resolved[src] { return hit }
            guard !src.contains("://"), !src.hasPrefix("data:"), !src.hasPrefix("cid:") else { return nil }
            let path = (src.components(separatedBy: CharacterSet(charactersIn: "?#")).first ?? src).removingPercentEncoding ?? src
            let file = path.hasPrefix("/") ? URL(fileURLWithPath: path) : baseDir.appendingPathComponent(path)
            guard let bytes = try? Data(contentsOf: file), bytes.count < 25_000_000 else { return nil }
            let key = "img\(attachments.count)"
            attachments[key] = QLPreviewReplyAttachment(data: bytes, contentType: UTType(filenameExtension: file.pathExtension) ?? .image)
            resolved[src] = "cid:\(key)"
            return "cid:\(key)"
        }

        let files = attachments
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            reply.attachments = files
            return Data(html.utf8)
        }
    }
}
