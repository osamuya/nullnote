import Foundation

/// コードブロックの中を、ごく粗く色分けするためのトークナイザ。
///
/// **キーワード・文字列・コメント・数値の4分類だけ。**
/// 型名と変数名の区別も、関数呼び出しの検出もしない。
/// 言語ごとの完全な構文解析は目指していない。
///
/// 依存を増やさずに「単色よりは読める」状態にすることが目的。
/// 本格的に必要になったら Highlightr の採用を検討する
/// （`docs/02-decision-log.md` の D-12）。
enum CodeSyntax {

    enum Kind: Hashable {
        case keyword
        case string
        case comment
        case number
    }

    struct Token: Hashable {
        let kind: Kind
        let range: Range<String.Index>
    }

    /// 行をまたぐブロックコメントを追跡するための状態。
    struct State: Hashable {
        var inBlockComment = false
    }

    struct Result {
        let tokens: [Token]
        let stateAfter: State
    }

    // MARK: - 言語の定義

    struct Language {
        let keywords: Set<String>
        /// 行コメントの開始。`//` `#` `--` など。
        let lineComments: [String]
        /// ブロックコメントの開始と終了。
        let blockComment: (open: String, close: String)?
        /// 文字列を囲む記号。
        let stringDelimiters: Set<Character>
        /// キーワードの大文字小文字を区別しないか。SQL のような言語で使う。
        var ignoresKeywordCase: Bool = false

        func isKeyword(_ word: String) -> Bool {
            keywords.contains(ignoresKeywordCase ? word.lowercased() : word)
        }
    }

    /// 言語名からその定義を引く。未知の言語や指定なしは `nil`（色分けしない）。
    ///
    /// 名前は ``` ```swift ``` の `swift` の部分。大文字小文字は無視する。
    static func language(named name: String?) -> Language? {
        guard let name = name?.lowercased(), !name.isEmpty else { return nil }
        return languages[name]
    }

    private static let cLike = (open: "/*", close: "*/")

    private static let languages: [String: Language] = {
        var table: [String: Language] = [:]

        func register(_ names: [String], _ language: Language) {
            for name in names { table[name] = language }
        }

        register(["swift"], Language(
            keywords: """
            associatedtype async await break case catch class continue default defer deinit do \
            else enum extension fallthrough false fileprivate for func guard if import in \
            indirect init inout internal is let nil open operator private protocol public \
            repeat rethrows return self Self static struct subscript super switch throw throws \
            true try typealias var where while some any nonisolated actor
            """.split(separator: " ").map(String.init).reduce(into: Set<String>()) { $0.insert($1) },
            lineComments: ["//"], blockComment: cLike, stringDelimiters: ["\""]))

        register(["javascript", "js", "typescript", "ts", "jsx", "tsx"], Language(
            keywords: Set("""
            async await break case catch class const continue debugger default delete do else \
            export extends false finally for from function if import in instanceof let new null \
            of return static super switch this throw true try typeof var void while with yield \
            interface type enum implements readonly public private protected as satisfies
            """.split(separator: " ").map(String.init)),
            lineComments: ["//"], blockComment: cLike, stringDelimiters: ["\"", "'", "`"]))

        register(["python", "py"], Language(
            keywords: Set("""
            and as assert async await break class continue def del elif else except False finally \
            for from global if import in is lambda None nonlocal not or pass raise return True \
            try while with yield match case self
            """.split(separator: " ").map(String.init)),
            lineComments: ["#"], blockComment: nil, stringDelimiters: ["\"", "'"]))

        register(["php"], Language(
            keywords: Set("""
            abstract and array as break callable case catch class clone const continue declare \
            default do echo else elseif empty enddeclare endfor endforeach endif endswitch \
            endwhile enum extends final finally fn for foreach function global goto if implements \
            include include_once instanceof insteadof interface isset list match namespace new or \
            print private protected public readonly require require_once return static switch \
            throw trait try unset use var while xor yield true false null
            """.split(separator: " ").map(String.init)),
            lineComments: ["//", "#"], blockComment: cLike, stringDelimiters: ["\"", "'"]))

        register(["bash", "sh", "zsh", "shell", "console"], Language(
            keywords: Set("""
            if then else elif fi for while until do done case esac function return break continue \
            local export readonly declare unset shift exit source alias echo cd set trap eval
            """.split(separator: " ").map(String.init)),
            lineComments: ["#"], blockComment: nil, stringDelimiters: ["\"", "'"]))

        register(["ruby", "rb"], Language(
            keywords: Set("""
            alias and begin break case class def defined do else elsif end ensure false for if in \
            module next nil not or redo rescue retry return self super then true undef unless \
            until when while yield require require_relative attr_accessor attr_reader
            """.split(separator: " ").map(String.init)),
            lineComments: ["#"], blockComment: nil, stringDelimiters: ["\"", "'"]))

        register(["c", "cpp", "c++", "objective-c", "objc", "java", "kotlin", "csharp", "cs", "go", "rust"], Language(
            keywords: Set("""
            auto break case char class const continue default delete do double else enum extern \
            false final float for func go goto if impl import int interface let long mut \
            namespace new nil null package private protected public return short signed sizeof \
            static struct switch template this throw true try type typedef union unsigned use \
            using var virtual void while
            """.split(separator: " ").map(String.init)),
            lineComments: ["//"], blockComment: cLike, stringDelimiters: ["\"", "'"]))

        register(["json"], Language(
            keywords: ["true", "false", "null"],
            lineComments: [], blockComment: nil, stringDelimiters: ["\""]))

        register(["sql"], Language(
            keywords: Set("""
            select from where insert into values update set delete create table alter drop index \
            join inner left right outer on group by order having limit offset as and or not null \
            distinct union all primary key foreign references default constraint
            """.split(separator: " ").map(String.init)),
            lineComments: ["--"], blockComment: cLike, stringDelimiters: ["'", "\""],
            ignoresKeywordCase: true))

        register(["yaml", "yml", "toml", "ini"], Language(
            keywords: ["true", "false", "null", "yes", "no"],
            lineComments: ["#"], blockComment: nil, stringDelimiters: ["\"", "'"]))

        return table
    }()

    // MARK: - 走査

    /// 1行分を走査する。
    ///
    /// ブロックコメントは行をまたぐので、`state` を次の行へ引き継ぐこと。
    static func tokenize(
        _ text: String,
        range: Range<String.Index>,
        language: Language,
        state: State = State()
    ) -> Result {
        var tokens: [Token] = []
        var state = state
        var index = range.lowerBound

        // ブロックコメントの途中から始まる行。
        if state.inBlockComment, let block = language.blockComment {
            if let close = find(block.close, in: text, from: index, limit: range.upperBound) {
                tokens.append(Token(kind: .comment, range: index..<close.upperBound))
                index = close.upperBound
                state.inBlockComment = false
            } else {
                if index < range.upperBound {
                    tokens.append(Token(kind: .comment, range: range))
                }
                return Result(tokens: tokens, stateAfter: state)
            }
        }

        while index < range.upperBound {
            let character = text[index]

            // 行コメント。行末まで。
            if let marker = language.lineComments.first(where: { starts(with: $0, in: text, at: index, limit: range.upperBound) }) {
                _ = marker
                tokens.append(Token(kind: .comment, range: index..<range.upperBound))
                return Result(tokens: tokens, stateAfter: state)
            }

            // ブロックコメント。
            if let block = language.blockComment, starts(with: block.open, in: text, at: index, limit: range.upperBound) {
                let afterOpen = text.index(index, offsetBy: block.open.count)
                if let close = find(block.close, in: text, from: afterOpen, limit: range.upperBound) {
                    tokens.append(Token(kind: .comment, range: index..<close.upperBound))
                    index = close.upperBound
                } else {
                    tokens.append(Token(kind: .comment, range: index..<range.upperBound))
                    state.inBlockComment = true
                    return Result(tokens: tokens, stateAfter: state)
                }
                continue
            }

            // 文字列。バックスラッシュのエスケープを飛ばす。行内で閉じなければ行末まで。
            if language.stringDelimiters.contains(character) {
                var cursor = text.index(after: index)
                var closed = false
                while cursor < range.upperBound {
                    if text[cursor] == "\\" {
                        cursor = text.index(after: cursor)
                        if cursor < range.upperBound { cursor = text.index(after: cursor) }
                        continue
                    }
                    if text[cursor] == character {
                        cursor = text.index(after: cursor)
                        closed = true
                        break
                    }
                    cursor = text.index(after: cursor)
                }
                _ = closed
                tokens.append(Token(kind: .string, range: index..<cursor))
                index = cursor
                continue
            }

            // 数値。識別子の途中（`utf8` の `8` など）は拾わない。
            if character.isNumber, !isIdentifierCharacter(previous(of: index, in: text, from: range.lowerBound)) {
                var cursor = index
                while cursor < range.upperBound,
                      text[cursor].isNumber || text[cursor] == "." || text[cursor] == "_"
                        || "xXbBoOeE".contains(text[cursor])
                        || (text[cursor].isHexDigit && text[cursor].isLetter) {
                    cursor = text.index(after: cursor)
                }
                tokens.append(Token(kind: .number, range: index..<cursor))
                index = cursor
                continue
            }

            // 識別子。キーワードなら色を付ける。
            if isIdentifierStart(character) {
                var cursor = index
                while cursor < range.upperBound, isIdentifierCharacter(text[cursor]) {
                    cursor = text.index(after: cursor)
                }
                if language.isKeyword(String(text[index..<cursor])) {
                    tokens.append(Token(kind: .keyword, range: index..<cursor))
                }
                index = cursor
                continue
            }

            index = text.index(after: index)
        }

        return Result(tokens: tokens, stateAfter: state)
    }

    // MARK: - 補助

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "$"
    }

    private static func isIdentifierCharacter(_ character: Character?) -> Bool {
        guard let character else { return false }
        return character.isLetter || character.isNumber || character == "_" || character == "$"
    }

    private static func previous(of index: String.Index, in text: String, from start: String.Index) -> Character? {
        guard index > start else { return nil }
        return text[text.index(before: index)]
    }

    private static func starts(with prefix: String, in text: String, at index: String.Index, limit: String.Index) -> Bool {
        var cursor = index
        for expected in prefix {
            guard cursor < limit, text[cursor] == expected else { return false }
            cursor = text.index(after: cursor)
        }
        return true
    }

    private static func find(_ needle: String, in text: String, from index: String.Index, limit: String.Index) -> Range<String.Index>? {
        var cursor = index
        while cursor < limit {
            if starts(with: needle, in: text, at: cursor, limit: limit) {
                return cursor..<text.index(cursor, offsetBy: needle.count)
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}
