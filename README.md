<p align="center"><img src="Resources/AppIcon.png" width="160" alt="Minicode icon"></p>

<h1 align="center">Minicode</h1>

<p align="center">A tiny, native macOS viewer and editor for Markdown and source code, with Quick Look previews.<br>
GitHub-style rendering, syntax highlighting, math, live preview. No Electron, about 3 MB.</p>

---

## Features

**Quick Look.** Select a Markdown or source file in Finder and press Space. Markdown is rendered like a GitHub README, and code is shown like a GitHub file: line numbers, syntax highlighting, and a header with the line count, size and language.

**App.** Double-click a Markdown file, or use **Open With ▸ Minicode** on a code file.

- **Markdown:** opens as a rendered page. Press ⌘E for an editor beside a live preview. The window grows to fit both panes if needed. Selecting a word in either pane selects it in the other.
- **Code:** opens in the GitHub-style view. Press ⌘E to switch to a full-width editor with syntax highlighting, line numbers and auto-indent.
- **A normal Mac document app:** autosave, Versions, Revert, Undo, Find, tabs, Open Recent, Print / Save as PDF, and zoom (⌘+ / ⌘− / ⌘0). Files reload automatically when they change on disk and you have no unsaved edits.

### Languages

Python, Rust, C, C++, C#, JavaScript, TypeScript, Solidity, Go, HTML, XML, CSS/SCSS, Shell (bash, zsh, sh), JSON, YAML, TOML, INI / `.env`, Dockerfile, Makefile, CMake, SQL, Swift, Java, Kotlin, Ruby, Lua, PHP, Haskell, Protocol Buffers, GraphQL, Terraform/HCL and diffs. Files are recognised by extension, by name (`Dockerfile`, `Makefile`, `.zshrc` and so on) or by their `#!` line. The same highlighting is used for fenced code blocks in Markdown.

### Markdown

- GitHub Flavored Markdown: tables, task lists, strikethrough, autolinks, reference-style links, raw HTML, and `> [!NOTE]`-style alerts.
- GitHub's stylesheet (fonts, spacing and colours), in light and dark mode.
- Math with KaTeX: `$…$`, `$$…$$`, ` ```math ` blocks and `` $`…`$ ``. ` ```latex ` / ` ```tex ` blocks are also rendered as math if they parse.
- Local images next to the file are displayed.

## Install

Requires macOS 12 or later and the Xcode Command Line Tools (`xcode-select --install`). Xcode itself isn't needed.

```bash
git clone https://github.com/randhindi/minicode.git
cd minicode
./build.sh install
```

This builds a universal (Apple Silicon and Intel) app, installs it to `~/Applications`, and registers the Quick Look extension. On first launch the app offers to become the default app for Markdown files. It registers for code files too, but as an alternative rather than the default, so it never takes them over from your editor.

If Finder still shows an old preview, run `qlmanage -r`. To uninstall, run `./build.sh uninstall`.

> [!NOTE]
> macOS identifies `.ts` files as MPEG-2 video. Minicode previews them as TypeScript when they contain text, and leaves real video files alone.

> [!NOTE]
> The app is ad-hoc signed, which is enough on the Mac that built it. Copying the built app to another Mac means getting past Gatekeeper (right-click ▸ Open). Building from source on each Mac avoids this.

## Development

```bash
./build.sh               # build build/Minicode.app
./build.sh test          # render Tests/cases/* and diff against Tests/expected/
./build.sh test --update # accept rendering changes
./build.sh render FILE   # print the preview HTML for any file
./build.sh icon          # regenerate the icon from Tools/make-icon.swift
```

### Layout

| Path | What it is |
|---|---|
| `Sources/Shared/Markdown.swift` | Markdown → HTML renderer (block and inline parser, no dependencies) |
| `Sources/Shared/Language.swift` | Language definitions: highlighting rules, keywords, file names |
| `Sources/Shared/Highlighter.swift` | Regex tokenizer that turns code into HTML |
| `Sources/Shared/CodeView.swift` | GitHub-style code view with line numbers |
| `Sources/Shared/Math.swift` | TeX → MathML, by running the bundled KaTeX in JavaScriptCore |
| `Sources/Shared/Page.swift` | HTML page wrapper and GitHub-derived CSS |
| `Sources/Extension/` | Quick Look preview extension (data-based HTML preview) |
| `Sources/App/` | The app: `NSDocument`, code editor (TextKit 1, line numbers, colouring), `WKWebView` preview, selection sync |
| `Resources/` | Info.plists, entitlements, icon, KaTeX |
| `Tools/` | Icon generator and the command-line renderer used by the tests |

### Adding a language

Add a `Language` in `Sources/Shared/Language.swift`: its rules, keywords and file extensions, then add it to `Language.all`. If macOS doesn't already know the extension, declare it in `UTImportedTypeDeclarations` in `Resources/App-Info.plist`, and add its type to `QLSupportedContentTypes` in `Resources/Extension-Info.plist`. Finally, add a sample to `Tests/cases/` and run `./build.sh test --update`.

### How it works

Markdown and code are converted to HTML in Swift. Math is turned into MathML ahead of time by KaTeX running in JavaScriptCore, and WebKit draws MathML natively. So the Quick Look preview runs no scripts and needs no web fonts. The editor colours text with the same tokenizer, as layout-only attributes, so colouring never touches the file or its undo history.

## Credits

- Math rendering by [KaTeX](https://katex.org) (MIT), bundled in `Resources/katex/`.
- Styling follows [github-markdown-css](https://github.com/sindresorhus/github-markdown-css). Alert icons are from [Octicons](https://github.com/primer/octicons) (MIT).

## License

[MIT](LICENSE)
