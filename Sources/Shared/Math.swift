import Foundation
import JavaScriptCore
import os

/// Renders TeX to MathML by running the bundled KaTeX in JavaScriptCore.
/// WebKit draws MathML natively, so the preview page needs no scripts or fonts.
enum MathRenderer {
    /// Location of `katex.min.js`. It ships once, in the app's Resources; the
    /// Quick Look extension (in Contents/PlugIns) finds it two levels up.
    static var scriptURL: URL? = {
        let bundle = Bundle(for: Marker.self)
        if let url = bundle.url(forResource: "katex.min", withExtension: "js") { return url }
        let shared = bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/katex.min.js")
        return FileManager.default.fileExists(atPath: shared.path) ? shared : nil
    }()

    private final class Marker {}
    private static let lock = NSLock()
    private static var loaded = false
    private static var render: JSValue?

    static func html(_ tex: String, display: Bool) -> String {
        if let out = tryHTML(tex, display: display, strict: false) { return out }
        let code = "<code>\(escapeHTML(tex))</code>"
        return display ? "<pre>\(code)</pre>" : code
    }

    /// Returns nil when KaTeX is unavailable or, with `strict`, when the TeX doesn't parse.
    static func tryHTML(_ tex: String, display: Bool, strict: Bool) -> String? {
        lock.lock(); defer { lock.unlock() }
        if !loaded {
            loaded = true
            let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MarkdownPreview", category: "math")
            if let url = scriptURL, let js = try? String(contentsOf: url, encoding: .utf8), let ctx = JSContext() {
                ctx.exceptionHandler = { _, e in log.error("katex js error: \(e?.toString() ?? "?", privacy: .public)") }
                ctx.evaluateScript(js)
                render = ctx.evaluateScript("""
                    (function (tex, display, strict) {
                      try {
                        return katex.renderToString(tex, { displayMode: display, output: "mathml", throwOnError: strict, strict: false, trust: false });
                      } catch (e) { return null; }
                    })
                    """)
            }
        }
        if let fn = render, let out = fn.call(withArguments: [tex, display, strict]), out.isString, let s = out.toString() {
            return display ? "<div class=\"math-display\">\(s)</div>" : s
        }
        return nil
    }
}
