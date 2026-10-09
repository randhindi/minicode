import Foundation

/// What a highlighted token is. Maps to GitHub's "prettylights" CSS classes in
/// HTML, and to the same palette in the editor.
enum TokenKind {
    case comment, keyword, string, constant, entity, variable, tag, attribute
    case inserted, deleted
    case heading, emphasis, code, link, listMarker, quote // Markdown, editor only

    var cssClass: String {
        switch self {
        case .comment, .quote: return "pl-c"
        case .keyword: return "pl-k"
        case .string, .link: return "pl-s"
        case .constant, .code: return "pl-c1"
        case .entity, .attribute: return "pl-en"
        case .variable, .listMarker: return "pl-v"
        case .tag: return "pl-ent"
        case .inserted: return "pl-mi1"
        case .deleted: return "pl-md"
        case .heading, .emphasis: return "pl-mh"
        }
    }
}

/// A language definition for the regex highlighter: an ordered list of rules
/// (earlier rules win at the same position) plus word lists for identifiers.
final class Language {
    enum Match {
        case token(TokenKind)
        case word // keyword / type / constant lookup, otherwise plain
        case call // like `word`, but an unknown name followed by `(` is an entity
    }

    let id: String
    let name: String
    let rules: [(String, Match)]
    let keywords: Set<String>
    let types: Set<String>
    let constants: Set<String>
    let caseInsensitive: Bool
    fileprivate(set) var extensions: [String] = []
    fileprivate(set) var fileNames: [String] = []
    fileprivate(set) var aliases: [String] = []
    fileprivate(set) var interpreters: [String] = []

    /// All rules as one alternation; each rule is wrapped in a capture group, so
    /// rule patterns must only use non-capturing groups.
    private(set) lazy var regex: NSRegularExpression = {
        let pattern = rules.map { "(\($0.0))" }.joined(separator: "|")
        return try! NSRegularExpression(pattern: pattern)
    }()

    init(_ id: String, _ name: String, rules: [(String, Match)], keywords: String = "", types: String = "",
         constants: String = "", caseInsensitive: Bool = false) {
        self.id = id
        self.name = name
        self.rules = rules
        self.caseInsensitive = caseInsensitive
        func words(_ s: String) -> Set<String> {
            Set(s.split(whereSeparator: \.isWhitespace).map { caseInsensitive ? $0.lowercased() : String($0) })
        }
        self.keywords = words(keywords)
        self.types = words(types)
        self.constants = words(constants)
    }

    fileprivate func files(_ exts: String, names: String = "", aliases: String = "", interpreters: String = "") -> Language {
        extensions = exts.split(separator: " ").map(String.init)
        fileNames = names.split(separator: " ").map(String.init)
        self.aliases = aliases.split(separator: " ").map(String.init)
        self.interpreters = interpreters.split(separator: " ").map(String.init)
        return self
    }
}

// MARK: - Lookup

extension Language {
    /// Finds a language by Markdown fence name (```py), extension or id.
    static func named(_ name: String) -> Language? {
        let key = name.lowercased()
        return byAlias[key] ?? byExtension[key]
    }

    /// Picks a language from a file name, falling back to the `#!` line.
    static func detect(fileName: String, firstLine: String? = nil) -> Language? {
        let lower = fileName.lowercased()
        if let lang = byFileName[lower] { return lang }
        if lower.hasPrefix(".env") { return ini }
        if lower.hasPrefix("dockerfile") || lower.hasPrefix("containerfile") { return dockerfile }
        let ext = (lower as NSString).pathExtension
        if !ext.isEmpty, let lang = byExtension[ext] { return lang }
        if let line = firstLine, line.hasPrefix("#!") {
            let words = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "/" })
            for word in words.reversed() {
                let program = word.trimmingCharacters(in: .decimalDigits.union(CharacterSet(charactersIn: ".")))
                if let lang = byInterpreter[program] { return lang }
            }
        }
        return nil
    }

    /// Every language that has file extensions, for type registration and docs.
    static let all: [Language] = [
        python, rust, c, cpp, csharp, javascript, typescript, solidity, go, html, xml, css, shell, json, yaml, toml,
        ini, dockerfile, makefile, cmake, sql, swift, java, kotlin, ruby, lua, php, haskell, proto, graphql, hcl, diff,
    ]

    private static let byExtension = index(\.extensions)
    private static let byFileName = index(\.fileNames)
    private static let byAlias = index { [$0.id] + $0.aliases + $0.extensions }
    private static let byInterpreter = index(\.interpreters)

    private static func index(_ keys: (Language) -> [String]) -> [String: Language] {
        var map: [String: Language] = [:]
        for lang in all { for key in keys(lang) where map[key] == nil { map[key] = lang } }
        return map
    }
}

// MARK: - Shared patterns

private enum P {
    static let dq = #""(?:\\.|[^"\\\n])*""#
    static let sq = #"'(?:\\.|[^'\\\n])*'"#
    static let bt = #"`(?:\\.|[^`\\])*`"#
    static let dqMulti = #""(?:\\.|[^"\\])*""#
    static let num = #"\b(?:0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|\d[\d_]*(?:\.\d[\d_]*)?(?:[eE][+-]?\d+)?)(?:[uUlLfFn]|[iu](?:8|16|32|64|128|size)|f32|f64)?\b"#
    static let ident = #"\b[A-Za-z_]\w*"#
    static let jsIdent = #"(?<![\w$])[A-Za-z_$][\w$]*"#
    static let call = #"\b[A-Za-z_]\w*(?=\s*\()"#
    static let cComments = #"//[^\n]*|/\*[\s\S]*?\*/"#
    static let hashComment = #"#[^\n]*"#
    static let wordHash = #"(?<![^\s;|&(])#[^\n]*"# // `#` only at the start of a word (shells, YAML)
    /// The name right after a declaring keyword, e.g. the `foo` in `def foo`.
    static func decl(_ keywords: String) -> String { #"(?<=\b(?:"# + keywords + #")\s{1,8})[A-Za-z_]\w*"# }
}

// MARK: - Languages

extension Language {
    static let python = Language("python", "Python", rules: [
        (P.hashComment, .token(.comment)),
        (#"(?:(?<!\w)[rRbBuUfF]{1,2})?(?:"""[\s\S]*?"""|'''[\s\S]*?'''|"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*')"#, .token(.string)),
        (P.decl("def|class"), .token(.entity)),
        (#"@[A-Za-z_][\w.]*"#, .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        and as assert async await break class continue def del elif else except finally for from global if import in \
        is lambda nonlocal not or pass raise return try while with yield match case
        """, constants: """
        True False None NotImplemented Ellipsis __name__ __file__ __init__ print len range int str float list dict set \
        tuple bool type isinstance issubclass super object open enumerate zip map filter sorted reversed sum min max abs \
        any all iter next repr hash id input format getattr setattr hasattr callable vars dir round ord chr bytes \
        frozenset property staticmethod classmethod Exception ValueError TypeError KeyError IndexError RuntimeError
        """).files("py pyw pyi", aliases: "py python3 gyp", interpreters: "python python3 python2 pypy uv")

    static let rust = Language("rust", "Rust", rules: [
        (P.cComments, .token(.comment)),
        (##"b?r#{0,3}"[\s\S]*?"#{0,3}|b?"(?:\\.|[^"\\])*"|b?'(?:\\(?:x[0-9a-fA-F]{2}|u\{[0-9a-fA-F]+\}|.)|[^\\'\n])'"##, .token(.string)),
        (#"'[A-Za-z_]\w*\b(?!')"#, .token(.keyword)), // lifetimes
        (#"#!?\[[^\]\n]*\]"#, .token(.constant)),      // attributes
        (#"\b[A-Za-z_]\w*!(?=\s*[(\[{])"#, .token(.entity)), // macros
        (P.decl("fn|struct|enum|trait|type|mod|union|impl"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut \
        pub ref return self Self static struct super trait type union unsafe use where while
        """, types: "i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str",
        constants: "true false None Some Ok Err").files("rs", aliases: "rs")

    private static let cKeywords = """
        auto break case const continue default do else enum extern for goto if inline register restrict return sizeof \
        static struct switch typedef union volatile while _Alignas _Alignof _Atomic _Bool _Generic _Noreturn \
        _Static_assert _Thread_local
        """
    private static let cTypes = """
        void char short int long float double signed unsigned bool size_t ssize_t ptrdiff_t int8_t int16_t int32_t \
        int64_t uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t FILE
        """
    private static let cRules: [(String, Match)] = [
        (P.cComments, .token(.comment)),
        (#"(?m)^[ \t]*#[ \t]*[A-Za-z]+"#, .token(.keyword)),
        (#"(?<=include)[ \t]*<[^>\n]*>"#, .token(.string)),
        (P.dq + "|" + P.sq, .token(.string)),
        (P.decl("struct|enum|union|class|namespace"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ]

    static let c = Language("c", "C", rules: cRules, keywords: cKeywords, types: cTypes,
                            constants: "NULL true false EOF stdin stdout stderr errno")
        .files("c h", aliases: "objc objective-c m")

    static let cpp = Language("cpp", "C++", rules: cRules, keywords: cKeywords + """
         alignas alignof and asm catch class concept consteval constexpr constinit const_cast co_await co_return \
        co_yield decltype delete dynamic_cast explicit export friend mutable namespace new noexcept not operator or \
        private protected public reinterpret_cast requires static_assert static_cast template this thread_local throw \
        try typeid typename using virtual xor override final
        """, types: cTypes + " auto wchar_t char8_t char16_t char32_t",
        constants: "NULL nullptr true false").files("cpp cc cxx c++ hpp hh hxx h++ ipp tpp ino mm", aliases: "c++")

    static let csharp = Language("csharp", "C#", rules: [
        (P.cComments, .token(.comment)),
        (#"@?\$?"(?:\\.|[^"\\\n])*"|"# + P.sq, .token(.string)),
        (#"(?m)^[ \t]*#[ \t]*[a-z]+"#, .token(.keyword)),
        (#"\[[A-Z]\w*(?:\([^)\n]*\))?\]"#, .token(.constant)),
        (P.decl("class|struct|interface|enum|record|namespace"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        abstract as async await base break case catch checked class const continue default delegate do else enum event \
        explicit extern finally fixed for foreach get goto if implicit in init interface internal is lock namespace new \
        operator out override params private protected public readonly record ref return sealed set sizeof stackalloc \
        static struct switch this throw try typeof unchecked unsafe using var virtual volatile when where while yield
        """, types: "bool byte char decimal double dynamic float int long object sbyte short string uint ulong ushort void",
        constants: "true false null").files("cs csx", aliases: "c# csharp")

    private static let jsKeywords = """
        async await break case catch class const continue debugger default delete do else export extends finally for \
        from function get if import in instanceof let new of return set static super switch this throw try typeof var \
        void while with yield as
        """
    private static let jsConstants = """
        true false null undefined NaN Infinity console window document globalThis Math JSON Object Array Promise String \
        Number Boolean Symbol Map Set WeakMap Error Date RegExp process require module exports
        """
    private static func jsRules(decorators: Bool) -> [(String, Match)] {
        var rules: [(String, Match)] = [
            (P.cComments, .token(.comment)),
            (P.dq + "|" + P.sq + "|" + P.bt, .token(.string)),
            (P.decl("function|class|interface|type|enum|namespace|extends|implements"), .token(.entity)),
        ]
        if decorators { rules.append((#"@[A-Za-z_][\w.]*"#, .token(.entity))) }
        return rules + [(P.call, .call), (P.num, .token(.constant)), (P.jsIdent, .word)]
    }

    static let javascript = Language("javascript", "JavaScript", rules: jsRules(decorators: false), keywords: jsKeywords,
                                     constants: jsConstants)
        .files("js mjs cjs jsx", aliases: "js node jsx", interpreters: "node deno bun")

    static let typescript = Language("typescript", "TypeScript", rules: jsRules(decorators: true), keywords: jsKeywords + """
         abstract declare enum implements interface is keyof namespace private protected public readonly type infer \
        satisfies unique override asserts
        """, types: "any boolean never number object string symbol unknown void bigint",
        constants: jsConstants).files("ts tsx mts cts", aliases: "ts tsx", interpreters: "ts-node tsx")

    static let solidity = Language("solidity", "Solidity", rules: [
        (P.cComments, .token(.comment)),
        (#"(?:hex|unicode)?(?:"# + P.dq + "|" + P.sq + ")", .token(.string)),
        (#"\b(?:u?int\d{0,3}|bytes\d{0,2}|u?fixed[\dx]*)\b"#, .token(.keyword)),
        (P.decl("contract|interface|library|function|modifier|event|error|struct|enum"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        pragma solidity import as from contract interface library abstract is using for function modifier event emit \
        error revert require assert returns return memory storage calldata transient public private internal external \
        view pure payable constant immutable override virtual struct enum mapping if else while do break continue new \
        delete try catch unchecked assembly fallback receive constructor anonymous indexed type let
        """, types: "address bool string byte",
        constants: """
        true false wei gwei ether seconds minutes hours days weeks msg block tx abi this super keccak256 sha256 \
        ripemd160 ecrecover addmod mulmod selfdestruct gasleft blockhash
        """).files("sol", aliases: "sol")

    static let go = Language("go", "Go", rules: [
        (P.cComments, .token(.comment)),
        (P.dq + "|" + P.bt + #"|'(?:\\.|[^'\\\n])+'"#, .token(.string)),
        (P.decl("func|type"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        break case chan const continue default defer else fallthrough for func go goto if import interface map package \
        range return select struct switch type var
        """, types: """
        bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 \
        uint32 uint64 uintptr any comparable
        """, constants: """
        true false nil iota append cap clear close complex copy delete imag len make max min new panic print println \
        real recover
        """).files("go", aliases: "golang")

    private static let markupRules: [(String, Match)] = [
        (#"<!--[\s\S]*?-->"#, .token(.comment)),
        (#"<!\[CDATA\[[\s\S]*?\]\]>"#, .token(.string)),
        (#"<![A-Za-z][^>]*>|<\?[\s\S]*?\?>"#, .token(.keyword)),
        (#"</?[A-Za-z][\w:.-]*"#, .token(.tag)),
        (#"(?<=\s)[\w:.@-]+(?=\s*=)"#, .token(.attribute)),
        (#"(?<==)\s*(?:"[^"]*"|'[^']*')"#, .token(.string)),
        (#"&#?\w+;"#, .token(.constant)),
    ]

    static let html = Language("html", "HTML", rules: markupRules).files("html htm xhtml vue svelte", aliases: "vue")
    static let xml = Language("xml", "XML", rules: markupRules).files("xml xsd xsl xslt svg plist storyboard xib csproj")

    static let css = Language("css", "CSS", rules: [
        (#"/\*[\s\S]*?\*/|(?<=\s)//[^\n]*"#, .token(.comment)),
        (P.dq + "|" + P.sq, .token(.string)),
        (#"@[\w-]+"#, .token(.keyword)),
        (#"#[0-9a-fA-F]{3,8}\b(?=[^{}]*[;}])"#, .token(.constant)),
        (#"-?(?:\d+\.?\d*|\.\d+)(?:%|[a-zA-Z]+)?"#, .token(.constant)),
        (#"!important"#, .token(.keyword)),
        (#"(?<![\w-])-{0,2}[a-zA-Z][\w-]*(?=\s*:[^;{}]*[;}])"#, .token(.constant)),
        (#"[.#][A-Za-z_-][\w-]*|::?[A-Za-z-]+"#, .token(.entity)),
        (#"\$[\w-]+"#, .token(.variable)),
        (#"[\w-]+(?=\()"#, .token(.constant)),
    ]).files("css scss sass less", aliases: "scss sass less")

    static let shell = Language("shell", "Shell", rules: [
        (P.wordHash, .token(.comment)),
        (#"\$'(?:\\.|[^'\\])*'|"(?:\\.|[^"\\])*"|'[^']*'"#, .token(.string)),
        (#"\$(?:\{[^}\n]*\}|[A-Za-z_]\w*|[0-9@#?*!$-])"#, .token(.variable)),
        (P.decl("function"), .token(.entity)),
        (#"(?m)^[ \t]*[A-Za-z_][\w-]*(?=\s*\(\s*\))"#, .token(.entity)),
        (#"(?<![\w$-])[A-Za-z_]\w*(?==)"#, .token(.variable)),
        (P.ident, .word),
    ], keywords: """
        if then elif else fi for while until do done case esac in function select return break continue local export \
        readonly declare typeset source alias unset shift exit time
        """, constants: "echo printf cd pwd read set eval exec trap test true false wait kill command type getopts let")
        .files("sh bash zsh ksh fish command", names: ".bashrc .zshrc .profile .bash_profile .zprofile .zshenv .bash_aliases",
               aliases: "bash zsh sh console shell-session", interpreters: "sh bash zsh ksh dash fish")

    static let json = Language("json", "JSON", rules: [
        (P.cComments, .token(.comment)),
        (#""(?:\\.|[^"\\\n])*"(?=\s*:)"#, .token(.tag)),
        (P.dq, .token(.string)),
        (#"-?\b\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b|\b(?:true|false|null)\b"#, .token(.constant)),
    ]).files("json jsonc json5 jsonl geojson ipynb webmanifest", names: ".prettierrc .eslintrc .babelrc composer.lock")

    static let yaml = Language("yaml", "YAML", rules: [
        (P.wordHash, .token(.comment)),
        (#"(?<![^\s{,])(?:"[^"\n]*"|'[^'\n]*'|[\w.$/@-][\w.$/@ -]*?)(?=:(?:\s|$))"#, .token(.tag)),
        (P.dq + "|" + P.sq, .token(.string)),
        (#"(?<![\w])[&*][\w-]+"#, .token(.variable)),
        (#"(?m)^(?:---|\.\.\.)\s*$"#, .token(.keyword)),
        (#"(?<![\w.-])(?:true|false|yes|no|null|~|-?\d+(?:\.\d+)?)(?![\w.-])"#, .token(.constant)),
    ]).files("yaml yml", names: ".clang-format", aliases: "yml")

    static let toml = Language("toml", "TOML", rules: [
        (P.hashComment, .token(.comment)),
        (#"(?m)^[ \t]*\[\[?[^\]\n]+\]\]?"#, .token(.entity)),
        (#"(?m)(?<![^\s{,])[\w.\-"']+(?=[ \t]*=)"#, .token(.tag)),
        (#""""[\s\S]*?"""|'''[\s\S]*?'''|"# + P.dq + "|" + P.sq, .token(.string)),
        (#"\d{4}-\d\d-\d\d(?:[T ][\d:.]+)?(?:Z|[+-]\d\d:\d\d)?|\b(?:true|false)\b|[+-]?\b\d[\d_]*(?:\.\d+)?(?:[eE][+-]?\d+)?\b"#, .token(.constant)),
    ]).files("toml", names: "cargo.lock pipfile poetry.lock uv.lock")

    static let ini = Language("ini", "INI", rules: [
        (#"(?m)^[ \t]*[#;][^\n]*"#, .token(.comment)),
        (#"(?m)^[ \t]*\[[^\]\n]+\]"#, .token(.entity)),
        (#"(?m)^[ \t]*(?:export[ \t]+)?[\w.-]+(?=[ \t]*[=:])"#, .token(.tag)),
        (P.dq + "|" + P.sq, .token(.string)),
        (#"\$\{?\w+\}?"#, .token(.variable)),
    ]).files("ini cfg conf env properties editorconfig gitconfig npmrc",
             names: ".gitconfig .editorconfig .npmrc .gitattributes .gitignore .dockerignore .gitmodules",
             aliases: "dotenv properties")

    static let dockerfile = Language("dockerfile", "Dockerfile", rules: [
        (#"(?m)^[ \t]*#[^\n]*"#, .token(.comment)),
        (#"(?im)^[ \t]*(?:FROM|RUN|CMD|LABEL|MAINTAINER|EXPOSE|ENV|ADD|COPY|ENTRYPOINT|VOLUME|USER|WORKDIR|ARG|ONBUILD|STOPSIGNAL|HEALTHCHECK|SHELL)\b|\b(?i:AS)\b"#, .token(.keyword)),
        (P.dq + "|" + P.sq, .token(.string)),
        (#"\$\{?\w+\}?"#, .token(.variable)),
        (#"(?<![\w-])--[\w-]+"#, .token(.constant)),
    ]).files("dockerfile containerfile", names: "dockerfile containerfile", aliases: "docker")

    static let makefile = Language("makefile", "Makefile", rules: [
        (P.hashComment, .token(.comment)),
        (#"(?m)^[ \t]*(?:ifeq|ifneq|ifdef|ifndef|else|endif|include|-include|define|endef|export|override|unexport|vpath)\b|\.PHONY|\.DEFAULT_GOAL"#, .token(.keyword)),
        (#"\$[({][^)}\n]*[)}]|\$[\w@<^?*%+]"#, .token(.variable)),
        (#"(?m)^[ \t]*[\w.-]+(?=[ \t]*[:+?!]?=)"#, .token(.variable)),
        (#"(?m)^[^\s:#=][^:#=\n]*(?=[ \t]*::?(?!=))"#, .token(.entity)),
        (P.dq + "|" + P.sq, .token(.string)),
    ]).files("mk mak make", names: "makefile gnumakefile justfile", aliases: "make just")

    static let cmake = Language("cmake", "CMake", rules: [
        (P.hashComment, .token(.comment)),
        (P.dqMulti, .token(.string)),
        (#"\$\{[^}\n]*\}"#, .token(.variable)),
        (P.call, .call), (P.ident, .word),
    ], keywords: "if elseif else endif foreach endforeach while endwhile function endfunction macro endmacro return",
        constants: "ON OFF TRUE FALSE YES NO PUBLIC PRIVATE INTERFACE REQUIRED")
        .files("cmake", names: "cmakelists.txt")

    static let sql = Language("sql", "SQL", rules: [
        (#"--[^\n]*|/\*[\s\S]*?\*/"#, .token(.comment)),
        (P.dq + "|" + P.sq, .token(.string)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        select from where insert into values update delete create table drop alter index join left right inner outer full \
        cross on group by order having limit offset distinct as and or not null is primary key foreign references default \
        exists union all case when then else end begin commit rollback returning with set view trigger function \
        procedure if replace unique check constraint cascade asc desc like ilike in between grant revoke database schema \
        explain analyze over partition window
        """, types: """
        int integer bigint smallint serial bigserial real double precision numeric decimal float boolean bool char \
        varchar text date time timestamp timestamptz interval uuid json jsonb bytea blob
        """, constants: "true false null count sum avg min max coalesce now", caseInsensitive: true)
        .files("sql psql pgsql mysql sqlite", aliases: "postgres postgresql plsql tsql")

    static let swift = Language("swift", "Swift", rules: [
        (P.cComments, .token(.comment)),
        (##"#?"""[\s\S]*?"""#?|"## + P.dq, .token(.string)),
        (#"[@#][A-Za-z_]\w*"#, .token(.keyword)),
        (P.decl("func|class|struct|enum|protocol|extension|actor|typealias"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        actor any as associatedtype async await break case catch class continue convenience default defer deinit \
        didSet do dynamic else enum extension fallthrough fileprivate final for func get guard if import in indirect \
        infix init inout internal is lazy let mutating nonisolated open operator optional override postfix precedencegroup \
        prefix private protocol public repeat required rethrows return self Self set some static struct subscript super \
        switch throw throws try typealias unowned var weak where while willSet consuming borrowing
        """, constants: "true false nil").files("swift", interpreters: "swift")

    static let java = Language("java", "Java", rules: [
        (P.cComments, .token(.comment)),
        (#""""[\s\S]*?"""|"# + P.dq + "|" + P.sq, .token(.string)),
        (#"@[A-Za-z_]\w*"#, .token(.keyword)),
        (P.decl("class|interface|enum|record"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        abstract assert break case catch class const continue default do else enum extends final finally for goto if \
        implements import instanceof interface native new package private protected public record return sealed permits \
        static strictfp super switch synchronized this throw throws transient try var void volatile while yield
        """, types: "boolean byte char double float int long short", constants: "true false null")
        .files("java groovy gradle", aliases: "groovy gradle")

    static let kotlin = Language("kotlin", "Kotlin", rules: [
        (P.cComments, .token(.comment)),
        (#""""[\s\S]*?"""|"# + P.dq + "|" + P.sq, .token(.string)),
        (#"@[A-Za-z_]\w*"#, .token(.keyword)),
        (P.decl("fun|class|interface|object|typealias"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        abstract annotation as break by catch class companion const constructor continue crossinline data do else enum \
        external final finally for fun get if import in infix init inline inner interface internal is lateinit noinline \
        object open operator out override package private protected public reified return sealed set super suspend \
        tailrec this throw try typealias val var vararg when where while
        """, constants: "true false null").files("kt kts", aliases: "kotlin kt")

    static let ruby = Language("ruby", "Ruby", rules: [
        (#"(?m)^=begin[\s\S]*?^=end"# + "|" + P.hashComment, .token(.comment)),
        (P.dq + "|" + P.sq, .token(.string)),
        (#"(?<![:\w]):[A-Za-z_]\w*[?!]?|\b[A-Za-z_]\w*:(?=\s)"#, .token(.constant)),
        (#"@{1,2}[A-Za-z_]\w*|\$[A-Za-z_]\w*"#, .token(.variable)),
        (P.decl("def|class|module"), .token(.entity)),
        (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        alias and begin break case class def defined do else elsif end ensure for if in module next not or redo rescue \
        retry return self super then undef unless until when while yield require require_relative attr_accessor \
        attr_reader attr_writer include extend private protected public raise lambda proc
        """, constants: "true false nil puts print p").files("rb rake gemspec ru", names: "gemfile rakefile podfile fastfile",
                                                          aliases: "rb", interpreters: "ruby")

    static let lua = Language("lua", "Lua", rules: [
        (#"--\[\[[\s\S]*?\]\]|--[^\n]*"#, .token(.comment)),
        (#"\[\[[\s\S]*?\]\]|"# + P.dq + "|" + P.sq, .token(.string)),
        (P.decl("function"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: "and break do else elseif end for function goto if in local not or repeat return then until while",
        constants: "true false nil self print require pairs ipairs type tostring tonumber").files("lua", interpreters: "lua")

    static let php = Language("php", "PHP", rules: [
        (P.cComments + "|" + P.hashComment, .token(.comment)),
        (P.dq + "|" + P.sq, .token(.string)),
        (#"<\?php|\?>"#, .token(.keyword)),
        (#"\$[A-Za-z_]\w*"#, .token(.variable)),
        (P.decl("function|class|interface|trait|enum"), .token(.entity)),
        (P.call, .call), (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        abstract and as break case catch class clone const continue declare default do echo else elseif enum extends \
        final finally fn for foreach function global if implements include include_once instanceof interface match \
        namespace new or private protected public readonly require require_once return static switch throw trait try \
        use var while yield
        """, constants: "true false null TRUE FALSE NULL").files("php", interpreters: "php")

    static let haskell = Language("haskell", "Haskell", rules: [
        (#"--[^\n]*|\{-[\s\S]*?-\}"#, .token(.comment)),
        (P.dq, .token(.string)),
        (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        case class data default deriving do else if import in infix infixl infixr instance let module newtype of then \
        type where qualified as hiding
        """, constants: "True False Nothing Just").files("hs lhs", aliases: "hs")

    static let proto = Language("proto", "Protocol Buffers", rules: [
        (P.cComments, .token(.comment)),
        (P.dq + "|" + P.sq, .token(.string)),
        (P.decl("message|service|enum|rpc"), .token(.entity)),
        (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        syntax edition package import option message service rpc returns enum oneof map repeated optional required \
        reserved extend stream public weak
        """, types: "double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes",
        constants: "true false").files("proto", aliases: "protobuf")

    static let graphql = Language("graphql", "GraphQL", rules: [
        (P.hashComment, .token(.comment)),
        (#""""[\s\S]*?"""|"# + P.dq, .token(.string)),
        (#"\$[A-Za-z_]\w*"#, .token(.variable)),
        (#"@[A-Za-z_]\w*"#, .token(.keyword)),
        (P.decl("type|input|enum|interface|union|scalar|fragment|query|mutation|subscription"), .token(.entity)),
        (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: """
        query mutation subscription fragment on type input enum interface union scalar schema extend directive implements
        """, constants: "true false null").files("graphql gql graphqls", aliases: "gql")

    static let hcl = Language("hcl", "HCL", rules: [
        (P.cComments + "|" + P.hashComment, .token(.comment)),
        (P.dq + #"|(?m)<<-?\w+[\s\S]*?^\s*\w+$"#, .token(.string)),
        (#"(?m)^[ \t]*[\w-]+(?=[ \t]*=)"#, .token(.tag)),
        (P.num, .token(.constant)), (P.ident, .word),
    ], keywords: "resource data variable output locals module provider terraform for in if else endif endfor dynamic",
        constants: "true false null").files("tf tfvars hcl nomad", aliases: "terraform")

    static let diff = Language("diff", "Diff", rules: [
        (#"(?m)^(?:\+\+\+|---)[^\n]*"#, .token(.keyword)),
        (#"(?m)^@@[^\n]*"#, .token(.constant)),
        (#"(?m)^\+[^\n]*"#, .token(.inserted)),
        (#"(?m)^-[^\n]*"#, .token(.deleted)),
        (#"(?m)^(?:diff|index|new file|deleted file|similarity|rename) [^\n]*"#, .token(.comment)),
    ]).files("diff patch", aliases: "patch")

    /// Markdown source, for the editor (rendered files use `MarkdownRenderer`).
    static let markdown = Language("markdown", "Markdown", rules: [
        (#"(?m)^ {0,3}```[^\n]*\n[\s\S]*?^ {0,3}```[ \t]*$|(?m)^ {0,3}~~~[^\n]*\n[\s\S]*?^ {0,3}~~~[ \t]*$"#, .token(.code)),
        (#"<!--[\s\S]*?-->"#, .token(.comment)),
        (#"(?m)^ {0,3}#{1,6}(?:[ \t][^\n]*)?$|(?m)^[^\n]+\n {0,3}(?:=+|-+)[ \t]*$"#, .token(.heading)),
        (#"(?m)^ {0,3}>[^\n]*"#, .token(.quote)),
        (#"(?m)^[ \t]*(?:[-*+]|\d{1,9}[.)])(?=[ \t])(?:[ \t]+\[[ xX]\])?"#, .token(.listMarker)),
        (#"`+[^`\n]+`+|\$\$[\s\S]+?\$\$|(?<![\\$])\$[^$\s][^$\n]*\$"#, .token(.code)),
        (#"!?\[[^\]\n]*\]\([^)\n]*\)|<https?://[^>\s]+>|^ {0,3}\[[^\]\n]+\]:[^\n]*"#, .token(.link)),
        (#"\*\*[^*\n]+\*\*|__[^_\n]+__|(?<![*\w])\*[^*\s][^*\n]*\*(?!\*)|(?<![\w])_[^_\s][^_\n]*_(?![\w])|~~[^~\n]+~~"#, .token(.emphasis)),
    ]).files("", aliases: "md")
}
