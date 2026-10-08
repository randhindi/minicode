import Foundation

enum Page {
    static func html(body: String, title: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark">
        <title>\(escapeHTML(title))</title>
        <style>\(css)</style>
        </head><body><article class="markdown-body">
        \(body)</article></body></html>
        """
    }

    /// Octicons used by GitHub for `> [!NOTE]`-style alerts.
    static let alertIcons: [String: String] = [
        "note": "M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z",
        "tip": "M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z",
        "important": "M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z",
        "warning": "M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z",
        "caution": "M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z",
    ]

    /// Mirrors github-markdown-css (GitHub's light/dark default themes).
    static let css = """
    :root{--fg:#1f2328;--muted:#59636e;--bg:#fff;--border:#d1d9e0;--border-muted:#d1d9e0b3;--subtle:#f6f8fa;
    --neutral:#818b981f;--link:#0969da;
    --pl-c:#59636e;--pl-k:#cf222e;--pl-s:#0a3069;--pl-c1:#0550ae;--pl-e:#6639ba;--pl-v:#953800;--pl-ent:#0550ae;
    --pl-mi:#116329;--pl-mi-bg:#dafbe1;--pl-md:#82071e;--pl-md-bg:#ffebe9;
    --hl:#fff8c5;--note:#0969da;--tip:#1a7f37;--important:#8250df;--warning:#9a6700;--caution:#d1242f}
    @media (prefers-color-scheme:dark){:root{--fg:#f0f6fc;--muted:#9198a1;--bg:#0d1117;--border:#3d444d;--border-muted:#3d444db3;
    --subtle:#151b23;--neutral:#656c7633;--link:#4493f8;
    --pl-c:#9198a1;--pl-k:#ff7b72;--pl-s:#a5d6ff;--pl-c1:#79c0ff;--pl-e:#d2a8ff;--pl-v:#ffa657;--pl-ent:#7ee787;
    --pl-mi:#aff5b4;--pl-mi-bg:#033a16;--pl-md:#ffdcd7;--pl-md-bg:#67060c;
    --hl:#bb800933;--note:#4493f8;--tip:#3fb950;--important:#ab7df8;--warning:#d29922;--caution:#f85149}}
    html,body{margin:0;background:var(--bg)}
    .markdown-body{box-sizing:border-box;min-width:200px;max-width:980px;margin:0 auto;padding:45px;
    color:var(--fg);background:var(--bg);-webkit-text-size-adjust:100%;
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","Noto Sans",Helvetica,Arial,sans-serif,"Apple Color Emoji","Segoe UI Emoji";
    font-size:16px;line-height:1.5;word-wrap:break-word}
    @media (max-width:767px){.markdown-body{padding:15px}}
    .markdown-body>:first-child{margin-top:0!important}
    .markdown-body>:last-child{margin-bottom:0!important}
    .markdown-body a{color:var(--link);text-decoration:none;background:transparent}
    .markdown-body a:hover{text-decoration:underline}
    .markdown-body b,.markdown-body strong{font-weight:600}
    .markdown-body h1,.markdown-body h2,.markdown-body h3,.markdown-body h4,.markdown-body h5,.markdown-body h6{
    margin-top:24px;margin-bottom:16px;font-weight:600;line-height:1.25}
    .markdown-body h1{margin:.67em 0;padding-bottom:.3em;font-size:2em;border-bottom:1px solid var(--border-muted)}
    .markdown-body h2{padding-bottom:.3em;font-size:1.5em;border-bottom:1px solid var(--border-muted)}
    .markdown-body h3{font-size:1.25em}
    .markdown-body h4{font-size:1em}
    .markdown-body h5{font-size:.875em}
    .markdown-body h6{font-size:.85em;color:var(--muted)}
    .markdown-body p,.markdown-body blockquote,.markdown-body ul,.markdown-body ol,.markdown-body dl,.markdown-body table,
    .markdown-body pre,.markdown-body details{margin-top:0;margin-bottom:16px}
    .markdown-body blockquote{margin-left:0;margin-right:0;padding:0 1em;color:var(--muted);border-left:.25em solid var(--border)}
    .markdown-body blockquote>:first-child{margin-top:0}
    .markdown-body blockquote>:last-child{margin-bottom:0}
    .markdown-body hr{box-sizing:content-box;overflow:hidden;height:.25em;padding:0;margin:24px 0;background-color:var(--border);border:0}
    .markdown-body ul,.markdown-body ol{padding-left:2em}
    .markdown-body ol ol,.markdown-body ul ol{list-style-type:lower-roman}
    .markdown-body ul ul ol,.markdown-body ul ol ol,.markdown-body ol ul ol,.markdown-body ol ol ol{list-style-type:lower-alpha}
    .markdown-body ul ul,.markdown-body ul ol,.markdown-body ol ol,.markdown-body ol ul{margin-top:0;margin-bottom:0}
    .markdown-body li>p{margin-top:16px}
    .markdown-body li+li{margin-top:.25em}
    .markdown-body .task-list-item{list-style-type:none}
    .markdown-body .task-list-item+.task-list-item{margin-top:.25rem}
    .markdown-body .task-list-item-checkbox{margin:0 .2em .25em -1.4em;vertical-align:middle}
    .markdown-body .contains-task-list{padding-left:2em}
    .markdown-body img{max-width:100%;box-sizing:content-box;border-style:none;background-color:var(--bg)}
    .markdown-body table{display:block;width:max-content;max-width:100%;overflow:auto;border-spacing:0;border-collapse:collapse;font-variant:tabular-nums}
    .markdown-body table th{font-weight:600}
    .markdown-body table th,.markdown-body table td{padding:6px 13px;border:1px solid var(--border)}
    .markdown-body table tr{background-color:var(--bg);border-top:1px solid var(--border-muted)}
    .markdown-body table tr:nth-child(2n){background-color:var(--subtle)}
    .markdown-body code,.markdown-body kbd,.markdown-body pre,.markdown-body samp,.markdown-body tt{
    font-family:ui-monospace,SFMono-Regular,"SF Mono",Menlo,Consolas,"Liberation Mono",monospace}
    .markdown-body code,.markdown-body tt{padding:.2em .4em;margin:0;font-size:85%;white-space:break-spaces;background-color:var(--neutral);border-radius:6px}
    .markdown-body pre{padding:16px;overflow:auto;font-size:85%;line-height:1.45;color:var(--fg);background-color:var(--subtle);border-radius:6px;word-wrap:normal}
    .markdown-body pre code{display:inline;padding:0;margin:0;overflow:visible;font-size:100%;line-height:inherit;
    word-wrap:normal;white-space:pre;background-color:transparent;border:0}
    .markdown-body h1 code,.markdown-body h2 code,.markdown-body h3 code,.markdown-body h4 code,.markdown-body h5 code,.markdown-body h6 code{padding:0 .2em;font-size:inherit}
    .markdown-body kbd{display:inline-block;padding:4px;font-size:11px;line-height:10px;color:var(--fg);vertical-align:middle;
    background-color:var(--subtle);border:solid 1px var(--border-muted);border-bottom-color:var(--border-muted);border-radius:6px;
    box-shadow:inset 0 -1px 0 var(--border-muted)}
    .markdown-body details summary{cursor:pointer}
    .markdown-body .md-active{background-color:var(--hl);box-shadow:0 0 0 4px var(--hl);border-radius:4px}
    .markdown-body math{font-family:"STIX Two Math","Latin Modern Math",math;font-size:1.15em}
    .markdown-body .math-display{margin:0 0 16px;overflow-x:auto;overflow-y:hidden;text-align:center}
    .markdown-body .katex-error{color:var(--caution)}
    .markdown-body .pl-c{color:var(--pl-c)}.markdown-body .pl-k{color:var(--pl-k)}.markdown-body .pl-s{color:var(--pl-s)}
    .markdown-body .pl-c1{color:var(--pl-c1)}.markdown-body .pl-e{color:var(--pl-e)}.markdown-body .pl-v{color:var(--pl-v)}
    .markdown-body .pl-ent{color:var(--pl-ent)}
    .markdown-body .pl-mi1{color:var(--pl-mi);background-color:var(--pl-mi-bg)}
    .markdown-body .pl-md{color:var(--pl-md);background-color:var(--pl-md-bg)}
    .markdown-body .markdown-alert{padding:.5rem 1rem;margin-bottom:16px;color:inherit;border-left:.25em solid var(--a)}
    .markdown-body .markdown-alert>:first-child{margin-top:0}
    .markdown-body .markdown-alert>:last-child{margin-bottom:0}
    .markdown-body .markdown-alert .markdown-alert-title{display:flex;font-weight:500;align-items:center;line-height:1;color:var(--a)}
    .markdown-body .markdown-alert .octicon{margin-right:.5rem;display:inline-block;overflow:visible!important;vertical-align:text-bottom;fill:currentColor}
    .markdown-body .markdown-alert-note{--a:var(--note)}.markdown-body .markdown-alert-tip{--a:var(--tip)}
    .markdown-body .markdown-alert-important{--a:var(--important)}.markdown-body .markdown-alert-warning{--a:var(--warning)}
    .markdown-body .markdown-alert-caution{--a:var(--caution)}
    """
}
