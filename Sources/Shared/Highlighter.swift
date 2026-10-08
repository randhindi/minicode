import Foundation

/// A tiny regex-based syntax highlighter. Not a parser — it only colors
/// comments, strings, numbers, keywords and type-like identifiers, which is
/// enough to make code blocks readable at a glance.
enum Highlighter {
    private struct Lang {
        let regex: NSRegularExpression
        let classes: [String]      // CSS class per capture group; "id" = keyword lookup
        var caseInsensitive = false
        var capitalizedTypes = true
        var keywords = Highlighter.keywords
    }

    static func highlight(_ code: String, lang: String) -> String {
        if lang == "diff" || lang == "patch" { return diff(code) }
        guard let spec = langs[aliases[lang] ?? lang] else { return escapeHTML(code) }
        let ns = code as NSString
        var out = "", last = 0
        for m in spec.regex.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
            out += escapeHTML(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            let tok = ns.substring(with: m.range)
            var cls: String?
            if let g = (1..<m.numberOfRanges).first(where: { m.range(at: $0).location != NSNotFound }) {
                cls = spec.classes[g - 1]
                if cls == "id" {
                    let key = spec.caseInsensitive ? tok.lowercased() : tok
                    cls = spec.keywords.contains(key) ? "k" : types.contains(key) ? "t"
                        : (spec.capitalizedTypes && tok.first!.isUppercase && tok.contains(where: \.isLowercase)) ? "t" : nil
                }
            }
            out += cls.map { "<span class=\"\(githubClass[$0] ?? $0)\">\(escapeHTML(tok))</span>" } ?? escapeHTML(tok)
            last = m.range.location + m.range.length
        }
        return out + escapeHTML(ns.substring(from: last))
    }

    /// Short token kinds → GitHub's "prettylights" CSS classes.
    private static let githubClass = ["c": "pl-c", "s": "pl-s", "n": "pl-c1", "k": "pl-k", "t": "pl-e", "v": "pl-v", "tg": "pl-ent"]

    private static func diff(_ code: String) -> String {
        code.components(separatedBy: "\n").map { line in
            let e = escapeHTML(line)
            if line.hasPrefix("+++") || line.hasPrefix("---") { return "<span class=\"pl-k\">\(e)</span>" }
            if line.hasPrefix("+") { return "<span class=\"pl-mi1\">\(e)</span>" }
            if line.hasPrefix("-") { return "<span class=\"pl-md\">\(e)</span>" }
            if line.hasPrefix("@@") { return "<span class=\"pl-c1\">\(e)</span>" }
            return e
        }.joined(separator: "\n")
    }

    private static func make(_ rules: [(String, String)], ci: Bool = false, caps: Bool = true, kw: Set<String> = keywords) -> Lang {
        let pattern = rules.map { "(\($0.0))" }.joined(separator: "|")
        return Lang(regex: try! NSRegularExpression(pattern: pattern), classes: rules.map(\.1), caseInsensitive: ci, capitalizedTypes: caps, keywords: kw)
    }

    private static let dq = #""(?:\\.|[^"\\\n])*""#
    private static let sq = #"'(?:\\.|[^'\\\n])*'"#
    private static let bt = #"`(?:\\.|[^`\\])*`"#
    private static let num = #"\b(?:0[xXbBoO][0-9a-fA-F_]+|\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?)\b"#
    private static let ident = #"\b[A-Za-z_][\w]*\b"#

    private static let langs: [String: Lang] = [
        "c": make([(#"//[^\n]*|/\*[\s\S]*?\*/"#, "c"), (dq + "|" + sq + "|" + bt, "s"), (num, "n"), (ident, "id")]),
        "rust": make([(#"//[^\n]*|/\*[\s\S]*?\*/"#, "c"), (dq + #"|'(?:\\.|[^'\\])'"#, "s"), (num, "n"), (ident, "id")]),
        "hash": make([(#"(?<![^\s])#[^\n]*"#, "c"), (#""""[\s\S]*?"""|'''[\s\S]*?'''|"# + dq + "|" + sq, "s"), (num, "n"), (ident, "id")]),
        "shell": make([(#"(?<![^\s])#[^\n]*"#, "c"), (dq + "|" + sq, "s"), (#"\$\{?[\w@#?*!-]+\}?"#, "v"), (ident, "id")], caps: false),
        "yaml": make([(#"(?<![^\s])#[^\n]*"#, "c"), (#"[\w.-]+(?=:(?:\s|$))"#, "tg"), (dq + "|" + sq, "s"), (num, "n")], caps: false),
        "sql": make([(#"--[^\n]*|/\*[\s\S]*?\*/"#, "c"), (dq + "|" + sq, "s"), (num, "n"), (ident, "id")], ci: true, caps: false, kw: sqlKeywords),
        "lua": make([(#"--\[\[[\s\S]*?\]\]|--[^\n]*"#, "c"), (dq + "|" + sq, "s"), (num, "n"), (ident, "id")]),
        "haskell": make([(#"--[^\n]*|\{-[\s\S]*?-\}"#, "c"), (dq, "s"), (num, "n"), (ident, "id")]),
        "css": make([(#"/\*[\s\S]*?\*/|//[^\n]*"#, "c"), (dq + "|" + sq, "s"), (#"#[0-9a-fA-F]{3,8}\b|-?\b\d+(?:\.\d+)?(?:px|em|rem|%|vh|vw|s|ms|deg)?"#, "n"), (#"[\w-]+(?=\s*:)"#, "n")]),
        "json": make([(#""(?:\\.|[^"\\])*"(?=\s*:)"#, "tg"), (dq, "s"), (#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b|\b(?:true|false|null)\b"#, "n")]),
        "html": make([(#"<!--[\s\S]*?-->"#, "c"), (#"</?[A-Za-z][\w:-]*|/?>"#, "tg"), (#""[^"]*"|'[^']*'"#, "s"), (#"\b[\w:-]+(?==)"#, "t")]),
    ]

    private static let aliases: [String: String] = {
        var a: [String: String] = [:]
        for k in "c h cpp c++ cc cxx hpp cs csharp java js javascript jsx mjs cjs ts typescript tsx swift go golang kotlin kt kts scala dart php objc objective-c objectivec m mm solidity sol groovy zig glsl hlsl proto protobuf jsonc json5 v d".split(separator: " ") { a[String(k)] = "c" }
        for k in "rs".split(separator: " ") { a[String(k)] = "rust" }
        for k in "python py python3 ruby rb perl pl r toml ini conf cfg nix elixir ex exs cmake makefile make dockerfile docker graphql gql julia jl crystal cr coffee coffeescript tcl powershell ps1 nim".split(separator: " ") { a[String(k)] = "hash" }
        for k in "sh bash zsh fish shell console shell-session ksh".split(separator: " ") { a[String(k)] = "shell" }
        for k in "yml".split(separator: " ") { a[String(k)] = "yaml" }
        for k in "psql postgres postgresql mysql sqlite plsql tsql".split(separator: " ") { a[String(k)] = "sql" }
        for k in "hs elm purescript".split(separator: " ") { a[String(k)] = "haskell" }
        for k in "scss sass less".split(separator: " ") { a[String(k)] = "css" }
        for k in "xml svg xhtml vue plist htm".split(separator: " ") { a[String(k)] = "html" }
        return a
    }()

    private static let keywords = Set("""
    abstract and as assert async await begin break case catch chan class const continue crate def default defer del \
    delete deinit do done dyn elif else elsif end ensure enum esac except export extends extension extern false fi \
    final finally fn for foreach from fun func function get global go goto guard if impl implements import in init \
    inline inout instanceof interface internal is lambda let local loop match mod module move mut mutating namespace \
    new nil none nonlocal not null object of open operator or override package pass private protected protocol pub \
    public raise range readonly ref repeat require rescue return sealed select self set some static struct subscript \
    super suspend switch then this throw throws trait true try type typealias typeof undefined union unless unsafe \
    until use using val var virtual void volatile when where while with yield None True False Self
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let sqlKeywords = Set("""
    select from where insert into values update delete create table drop alter index join left right inner outer on \
    group by order having limit offset distinct as and or not null is primary key foreign references default exists \
    union all case when then else end begin commit rollback returning with set true false
    """.split(whereSeparator: \.isWhitespace).map(String.init))

    private static let types = Set("""
    int uint int8 int16 int32 int64 uint8 uint16 uint32 uint64 i8 i16 i32 i64 i128 u8 u16 u32 u64 u128 isize usize \
    f32 f64 float double bool boolean char str string byte short long unsigned signed size_t any unknown never number \
    bigint symbol integer text varchar serial timestamp date
    """.split(whereSeparator: \.isWhitespace).map(String.init))
}
