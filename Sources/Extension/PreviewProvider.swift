import Foundation
import QuickLookUI
import UniformTypeIdentifiers

@objc(PreviewProvider)
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let url = request.fileURL
        let data = try Data(contentsOf: url)
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        // Local images are shipped to the preview as attachments, referenced by `cid:`.
        let baseDir = url.deletingLastPathComponent()
        var attachments: [String: QLPreviewReplyAttachment] = [:]
        var resolved: [String: String] = [:]
        let renderer = MarkdownRenderer()
        renderer.imageResolver = { src in
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

        let html = Page.html(body: renderer.render(text), title: url.lastPathComponent)
        let files = attachments
        return QLPreviewReply(dataOfContentType: .html, contentSize: CGSize(width: 900, height: 1100)) { reply in
            reply.stringEncoding = .utf8
            reply.attachments = files
            return Data(html.utf8)
        }
    }
}
