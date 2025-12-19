import SwiftUI

/// Lightweight syntax highlighter for code viewing
/// Uses pattern matching for common code elements - optimized for mobile viewing
enum SyntaxHighlighter {
    // MARK: - Public API

    /// Highlight a single line of code
    /// - Parameters:
    ///   - line: The source code line
    ///   - language: Programming language for keyword highlighting
    /// - Returns: Attributed string with syntax colors
    static func highlight(line: String, language: Language) -> AttributedString {
        guard !line.isEmpty else {
            return AttributedString(" ")
        }

        var result = AttributedString(line)

        // Apply highlighting in order of priority (most specific first)
        // Later matches override earlier ones for overlapping ranges
        applyComments(to: &result, line: line, language: language)
        applyStrings(to: &result, line: line, language: language)
        applyNumbers(to: &result, line: line)
        applyDecorators(to: &result, line: line, language: language)
        applyKeywords(to: &result, line: line, language: language)
        applyTypes(to: &result, line: line, language: language)

        return result
    }

    /// Detect language from file extension
    static func detectLanguage(from extension: String?) -> Language {
        guard let ext = `extension`?.lowercased() else { return .plainText }

        switch ext {
        case "swift": return .swift
        case "js", "jsx", "mjs", "cjs": return .javascript
        case "ts", "tsx", "mts": return .typescript
        case "py", "pyw": return .python
        case "go": return .go
        case "rs": return .rust
        case "rb", "erb": return .ruby
        case "java": return .java
        case "kt", "kts": return .kotlin
        case "c", "h": return .c
        case "cpp", "cc", "cxx", "hpp": return .cpp
        case "cs": return .csharp
        case "php": return .php
        case "sh", "bash", "zsh": return .shell
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "html", "htm": return .html
        case "css", "scss", "sass", "less": return .css
        case "sql": return .sql
        case "md", "markdown": return .markdown
        default: return .plainText
        }
    }

    // MARK: - Language Definition

    enum Language {
        case swift
        case javascript
        case typescript
        case python
        case go
        case rust
        case ruby
        case java
        case kotlin
        case c
        case cpp
        case csharp
        case php
        case shell
        case json
        case yaml
        case html
        case css
        case sql
        case markdown
        case plainText

        /// Single-line comment prefix
        var singleLineComment: String? {
            switch self {
            case .python, .ruby, .shell, .yaml:
                return "#"
            case .sql:
                return "--"
            case .html, .css, .markdown, .json, .plainText:
                return nil
            default:
                return "//"
            }
        }

        /// Multi-line comment start
        var multiLineCommentStart: String? {
            switch self {
            case .python:
                return nil  // Python uses ''' or """ for docstrings, handled in strings
            case .ruby:
                return "=begin"
            case .html:
                return "<!--"
            case .css:
                return "/*"
            case .shell, .yaml, .json, .sql, .markdown, .plainText:
                return nil
            default:
                return "/*"
            }
        }

        /// Keywords for this language
        var keywords: Set<String> {
            switch self {
            case .swift:
                return ["func", "class", "struct", "enum", "protocol", "extension",
                        "var", "let", "if", "else", "guard", "switch", "case", "default",
                        "for", "while", "repeat", "in", "return", "throw", "throws",
                        "try", "catch", "import", "private", "public", "internal",
                        "fileprivate", "open", "static", "final", "override", "init",
                        "deinit", "self", "super", "nil", "true", "false", "as", "is",
                        "where", "async", "await", "actor", "some", "any", "weak",
                        "unowned", "lazy", "mutating", "nonmutating", "convenience",
                        "required", "optional", "inout", "typealias", "associatedtype",
                        "break", "continue", "fallthrough", "defer", "do", "get", "set",
                        "willSet", "didSet", "subscript", "indirect", "precedencegroup",
                        "operator", "infix", "prefix", "postfix", "rethrows"]

            case .javascript, .typescript:
                return ["function", "const", "let", "var", "if", "else", "switch",
                        "case", "default", "for", "while", "do", "break", "continue",
                        "return", "throw", "try", "catch", "finally", "class", "extends",
                        "new", "this", "super", "import", "export", "from", "as",
                        "async", "await", "yield", "static", "get", "set", "typeof",
                        "instanceof", "in", "of", "delete", "void", "null", "undefined",
                        "true", "false", "debugger", "with", "enum", "implements",
                        "interface", "package", "private", "protected", "public",
                        "type", "declare", "namespace", "module", "readonly", "keyof",
                        "infer", "never", "unknown", "any", "abstract", "override"]

            case .python:
                return ["def", "class", "if", "elif", "else", "for", "while", "try",
                        "except", "finally", "with", "as", "import", "from", "return",
                        "yield", "raise", "pass", "break", "continue", "and", "or",
                        "not", "in", "is", "lambda", "global", "nonlocal", "assert",
                        "del", "True", "False", "None", "async", "await", "match",
                        "case", "self", "cls"]

            case .go:
                return ["func", "type", "struct", "interface", "map", "chan", "package",
                        "import", "var", "const", "if", "else", "switch", "case",
                        "default", "for", "range", "break", "continue", "return",
                        "go", "defer", "select", "fallthrough", "goto", "nil", "true",
                        "false", "iota", "make", "new", "append", "len", "cap", "copy",
                        "delete", "panic", "recover", "close", "complex", "real", "imag"]

            case .rust:
                return ["fn", "let", "mut", "const", "static", "if", "else", "match",
                        "loop", "while", "for", "in", "break", "continue", "return",
                        "struct", "enum", "trait", "impl", "type", "mod", "use", "pub",
                        "crate", "super", "self", "Self", "where", "as", "ref", "move",
                        "async", "await", "dyn", "unsafe", "extern", "true", "false",
                        "Some", "None", "Ok", "Err", "Box", "Vec", "String", "Option",
                        "Result", "macro_rules"]

            case .ruby:
                return ["def", "class", "module", "if", "elsif", "else", "unless",
                        "case", "when", "while", "until", "for", "do", "end", "begin",
                        "rescue", "ensure", "raise", "return", "yield", "break", "next",
                        "redo", "retry", "self", "super", "nil", "true", "false",
                        "and", "or", "not", "in", "then", "alias", "defined?",
                        "private", "protected", "public", "attr_reader", "attr_writer",
                        "attr_accessor", "require", "require_relative", "include",
                        "extend", "prepend", "lambda", "proc"]

            case .java:
                return ["class", "interface", "enum", "extends", "implements", "public",
                        "private", "protected", "static", "final", "abstract", "native",
                        "synchronized", "volatile", "transient", "strictfp", "void",
                        "if", "else", "switch", "case", "default", "for", "while", "do",
                        "break", "continue", "return", "throw", "throws", "try", "catch",
                        "finally", "new", "this", "super", "instanceof", "import",
                        "package", "true", "false", "null", "assert", "var", "record",
                        "sealed", "permits", "non-sealed", "yield"]

            case .kotlin:
                return ["fun", "val", "var", "class", "object", "interface", "enum",
                        "sealed", "data", "open", "abstract", "override", "final",
                        "private", "protected", "public", "internal", "if", "else",
                        "when", "for", "while", "do", "break", "continue", "return",
                        "throw", "try", "catch", "finally", "import", "package", "as",
                        "is", "in", "out", "this", "super", "null", "true", "false",
                        "companion", "constructor", "init", "get", "set", "by", "lazy",
                        "lateinit", "suspend", "inline", "crossinline", "noinline",
                        "reified", "typealias", "where", "annotation"]

            case .c, .cpp:
                return ["if", "else", "switch", "case", "default", "for", "while", "do",
                        "break", "continue", "return", "goto", "sizeof", "typedef",
                        "struct", "union", "enum", "const", "static", "extern", "auto",
                        "register", "volatile", "inline", "void", "int", "char", "short",
                        "long", "float", "double", "signed", "unsigned", "true", "false",
                        "NULL", "nullptr", "class", "public", "private", "protected",
                        "virtual", "override", "final", "new", "delete", "this",
                        "template", "typename", "namespace", "using", "try", "catch",
                        "throw", "noexcept", "constexpr", "auto", "decltype", "concept",
                        "requires", "co_await", "co_return", "co_yield", "module",
                        "import", "export"]

            case .csharp:
                return ["class", "struct", "interface", "enum", "record", "namespace",
                        "using", "public", "private", "protected", "internal", "static",
                        "readonly", "const", "virtual", "override", "abstract", "sealed",
                        "new", "this", "base", "if", "else", "switch", "case", "default",
                        "for", "foreach", "while", "do", "break", "continue", "return",
                        "throw", "try", "catch", "finally", "lock", "using", "yield",
                        "async", "await", "var", "dynamic", "object", "string", "int",
                        "bool", "void", "null", "true", "false", "is", "as", "in", "out",
                        "ref", "params", "get", "set", "init", "value", "where",
                        "delegate", "event", "partial", "extern", "unsafe", "fixed",
                        "sizeof", "typeof", "nameof", "stackalloc", "checked", "unchecked"]

            case .php:
                return ["function", "class", "interface", "trait", "extends", "implements",
                        "public", "private", "protected", "static", "final", "abstract",
                        "const", "var", "if", "else", "elseif", "switch", "case", "default",
                        "for", "foreach", "while", "do", "break", "continue", "return",
                        "throw", "try", "catch", "finally", "new", "clone", "instanceof",
                        "use", "namespace", "as", "global", "echo", "print", "include",
                        "require", "include_once", "require_once", "true", "false", "null",
                        "array", "callable", "iterable", "object", "bool", "int", "float",
                        "string", "void", "mixed", "never", "self", "parent", "static",
                        "fn", "match", "enum", "readonly"]

            case .shell:
                return ["if", "then", "else", "elif", "fi", "case", "esac", "for", "while",
                        "until", "do", "done", "in", "function", "select", "time", "coproc",
                        "break", "continue", "return", "exit", "export", "readonly", "local",
                        "declare", "typeset", "unset", "shift", "source", "alias", "unalias",
                        "true", "false", "echo", "printf", "read", "cd", "pwd", "pushd",
                        "popd", "dirs", "set", "eval", "exec", "trap", "wait", "test"]

            case .json:
                return ["true", "false", "null"]

            case .yaml:
                return ["true", "false", "null", "yes", "no", "on", "off"]

            case .html:
                return []

            case .css:
                return ["important", "inherit", "initial", "unset", "revert", "auto",
                        "none", "normal", "block", "inline", "flex", "grid", "hidden",
                        "visible", "absolute", "relative", "fixed", "sticky", "static"]

            case .sql:
                return ["SELECT", "FROM", "WHERE", "AND", "OR", "NOT", "IN", "LIKE",
                        "ORDER", "BY", "ASC", "DESC", "GROUP", "HAVING", "JOIN", "LEFT",
                        "RIGHT", "INNER", "OUTER", "ON", "AS", "INSERT", "INTO", "VALUES",
                        "UPDATE", "SET", "DELETE", "CREATE", "TABLE", "INDEX", "VIEW",
                        "DROP", "ALTER", "ADD", "COLUMN", "PRIMARY", "KEY", "FOREIGN",
                        "REFERENCES", "UNIQUE", "NULL", "DEFAULT", "CONSTRAINT", "CHECK",
                        "CASE", "WHEN", "THEN", "ELSE", "END", "UNION", "ALL", "DISTINCT",
                        "LIMIT", "OFFSET", "FETCH", "TOP", "PERCENT", "EXISTS", "BETWEEN",
                        "IS", "CAST", "CONVERT", "COALESCE", "NULLIF", "COUNT", "SUM",
                        "AVG", "MIN", "MAX", "GRANT", "REVOKE", "COMMIT", "ROLLBACK",
                        "TRANSACTION", "BEGIN", "DECLARE", "CURSOR", "OPEN", "CLOSE",
                        "FETCH", "IF", "WHILE", "RETURN", "EXEC", "EXECUTE", "PROCEDURE",
                        "FUNCTION", "TRIGGER", "DATABASE", "SCHEMA", "USE", "SHOW",
                        "DESCRIBE", "EXPLAIN", "TRUE", "FALSE"]

            case .markdown, .plainText:
                return []
            }
        }

        /// Whether this language uses uppercase for types
        var highlightUppercaseTypes: Bool {
            switch self {
            case .swift, .java, .kotlin, .csharp, .rust, .go, .typescript:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Private Highlighting Methods

    /// Apply comment highlighting
    private static func applyComments(to result: inout AttributedString, line: String, language: Language) {
        // Single-line comments
        if let prefix = language.singleLineComment,
           let range = line.range(of: prefix) {
            let startIndex = line.distance(from: line.startIndex, to: range.lowerBound)
            if let attrRange = Range(NSRange(location: startIndex, length: line.count - startIndex), in: result) {
                result[attrRange].foregroundColor = ColorSystem.Syntax.comment
            }
            return  // Rest of line is comment, skip other highlighting
        }

        // Multi-line comment start (partial support - highlights from /* to end of line)
        if let start = language.multiLineCommentStart,
           let range = line.range(of: start) {
            let startIndex = line.distance(from: line.startIndex, to: range.lowerBound)
            if let attrRange = Range(NSRange(location: startIndex, length: line.count - startIndex), in: result) {
                result[attrRange].foregroundColor = ColorSystem.Syntax.comment
            }
        }
    }

    /// Apply string highlighting
    private static func applyStrings(to result: inout AttributedString, line: String, language: Language) {
        // Match strings: "...", '...', `...` (for JS template literals)
        // Simplified: doesn't handle escaped quotes perfectly
        let patterns: [(pattern: String, color: Color)] = [
            (#"\"\"\"[^\"]*\"\"\""#, ColorSystem.Syntax.string),  // Triple double quotes
            (#"'''[^']*'''"#, ColorSystem.Syntax.string),         // Triple single quotes
            (#"\"(?:[^\"\\]|\\.)*\""#, ColorSystem.Syntax.string), // Double quoted
            (#"'(?:[^'\\]|\\.)*'"#, ColorSystem.Syntax.string),   // Single quoted
            (#"`(?:[^`\\]|\\.)*`"#, ColorSystem.Syntax.string),   // Backtick (template)
        ]

        for (pattern, color) in patterns {
            applyPattern(pattern, color: color, to: &result, line: line)
        }
    }

    /// Apply number highlighting
    private static func applyNumbers(to result: inout AttributedString, line: String) {
        // Hex, binary, octal, float, integer
        let patterns = [
            #"0[xX][0-9a-fA-F_]+"#,        // Hex
            #"0[bB][01_]+"#,                // Binary
            #"0[oO][0-7_]+"#,               // Octal
            #"\b\d+\.\d+([eE][+-]?\d+)?\b"#, // Float
            #"\b\d+[eE][+-]?\d+\b"#,         // Scientific
            #"\b\d+\b"#,                     // Integer
        ]

        for pattern in patterns {
            applyPattern(pattern, color: ColorSystem.Syntax.number, to: &result, line: line)
        }
    }

    /// Apply decorator/attribute highlighting (@something)
    private static func applyDecorators(to result: inout AttributedString, line: String, language: Language) {
        switch language {
        case .swift, .java, .kotlin, .python, .typescript:
            applyPattern(#"@\w+"#, color: ColorSystem.Syntax.decorator, to: &result, line: line)
        case .rust:
            applyPattern(#"#\[[\w:]+(?:\([^\)]*\))?\]"#, color: ColorSystem.Syntax.decorator, to: &result, line: line)
        case .csharp:
            applyPattern(#"\[\w+(?:\([^\)]*\))?\]"#, color: ColorSystem.Syntax.decorator, to: &result, line: line)
        case .php:
            applyPattern(#"#\[\w+(?:\([^\)]*\))?\]"#, color: ColorSystem.Syntax.decorator, to: &result, line: line)
        default:
            break
        }
    }

    /// Apply keyword highlighting
    private static func applyKeywords(to result: inout AttributedString, line: String, language: Language) {
        let keywords = language.keywords
        guard !keywords.isEmpty else { return }

        // SQL keywords are case-insensitive
        let caseSensitive = language != .sql

        for keyword in keywords {
            let pattern = #"\b"# + NSRegularExpression.escapedPattern(for: keyword) + #"\b"#
            let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
            applyPattern(pattern, color: ColorSystem.Syntax.keyword, to: &result, line: line, options: options)
        }
    }

    /// Apply type highlighting (capitalized identifiers)
    private static func applyTypes(to result: inout AttributedString, line: String, language: Language) {
        guard language.highlightUppercaseTypes else { return }

        // Match PascalCase identifiers (types in Swift, Java, etc.)
        // Excludes keywords which are already highlighted
        applyPattern(#"\b[A-Z][a-zA-Z0-9_]*\b"#, color: ColorSystem.Syntax.type, to: &result, line: line)
    }

    /// Apply a regex pattern with a color
    private static func applyPattern(
        _ pattern: String,
        color: Color,
        to result: inout AttributedString,
        line: String,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }

        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = regex.matches(in: line, options: [], range: nsRange)

        for match in matches {
            if let attrRange = Range(match.range, in: result) {
                result[attrRange].foregroundColor = color
            }
        }
    }
}
