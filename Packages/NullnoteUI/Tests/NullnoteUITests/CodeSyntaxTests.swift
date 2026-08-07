import Foundation
import Testing
@testable import NullnoteUI

@Suite("コードの簡易ハイライト")
struct CodeSyntaxTests {

    /// 走査結果を「種別 → 該当文字列」の並びに落とす。
    func tokens(_ code: String, _ languageName: String) -> [(CodeSyntax.Kind, String)] {
        guard let language = CodeSyntax.language(named: languageName) else { return [] }
        var state = CodeSyntax.State()
        var result: [(CodeSyntax.Kind, String)] = []
        var lineStart = code.startIndex
        while lineStart <= code.endIndex {
            let lineEnd = code[lineStart...].firstIndex(where: \.isNewline) ?? code.endIndex
            let outcome = CodeSyntax.tokenize(code, range: lineStart..<lineEnd, language: language, state: state)
            state = outcome.stateAfter
            result += outcome.tokens.map { ($0.kind, String(code[$0.range])) }
            guard lineEnd < code.endIndex else { break }
            lineStart = code.index(after: lineEnd)
        }
        return result
    }

    func texts(_ code: String, _ language: String, _ kind: CodeSyntax.Kind) -> [String] {
        tokens(code, language).filter { $0.0 == kind }.map(\.1)
    }

    // MARK: - 言語の判別

    @Test("言語名から定義を引ける", arguments: ["swift", "Swift", "SWIFT", "js", "python", "bash", "php", "json", "sql"])
    func knownLanguages(name: String) {
        #expect(CodeSyntax.language(named: name) != nil)
    }

    @Test("未知の言語や指定なしは色分けしない")
    func unknownLanguage() {
        #expect(CodeSyntax.language(named: nil) == nil)
        #expect(CodeSyntax.language(named: "") == nil)
        #expect(CodeSyntax.language(named: "brainfuck") == nil)
    }

    // MARK: - 4分類

    @Test("キーワード")
    func keywords() {
        #expect(texts("let x = 1", "swift", .keyword) == ["let"])
        #expect(texts("func hello() { return }", "swift", .keyword) == ["func", "return"])
        #expect(texts("def main(): pass", "python", .keyword) == ["def", "pass"])
        #expect(texts("SELECT * FROM users", "sql", .keyword) == ["SELECT", "FROM"])
    }

    @Test("キーワードに似た識別子は拾わない")
    func identifiersThatContainKeywords() {
        // letter は let で始まるが別の語。returnValue も同じ。
        #expect(texts("letter = returnValue", "swift", .keyword).isEmpty)
    }

    @Test("文字列")
    func strings() {
        #expect(texts(#"let s = "hello""#, "swift", .string) == [#""hello""#])
        #expect(texts("x = 'a' + \"b\"", "python", .string) == ["'a'", "\"b\""])
    }

    @Test("文字列の中のエスケープされた引用符では閉じない")
    func escapedQuote() {
        #expect(texts(#"let s = "a\"b" + c"#, "swift", .string) == [#""a\"b""#])
    }

    @Test("文字列の中のキーワードは色を付けない")
    func keywordInsideString() {
        #expect(texts(#"let s = "return let func""#, "swift", .keyword) == ["let"])
    }

    @Test("行コメント")
    func lineComments() {
        #expect(texts("let x = 1 // これは説明", "swift", .comment) == ["// これは説明"])
        #expect(texts("x = 1 # 説明", "python", .comment) == ["# 説明"])
        #expect(texts("SELECT 1 -- 説明", "sql", .comment) == ["-- 説明"])
    }

    @Test("コメントの中のキーワードや文字列は色を付けない")
    func insideComment() {
        let code = #"// let x = "a""#
        #expect(texts(code, "swift", .comment) == [code])
        #expect(texts(code, "swift", .keyword).isEmpty)
        #expect(texts(code, "swift", .string).isEmpty)
    }

    @Test("ブロックコメントが行をまたいでも続く")
    func multiLineBlockComment() {
        let code = """
        let a = 1
        /* ここから
           let b = 2
           ここまで */
        let c = 3
        """
        let keywords = texts(code, "swift", .keyword)
        // コメントの中の let は拾わない。外側の2つだけ。
        #expect(keywords == ["let", "let"])
        #expect(texts(code, "swift", .comment).count == 3)  // 3行にまたがる
    }

    @Test("同じ行で閉じるブロックコメント")
    func inlineBlockComment() {
        #expect(texts("let /* 補足 */ x = 1", "swift", .comment) == ["/* 補足 */"])
        #expect(texts("let /* 補足 */ x = 1", "swift", .keyword) == ["let"])
    }

    @Test("数値")
    func numbers() {
        #expect(texts("let x = 42", "swift", .number) == ["42"])
        #expect(texts("let x = 3.14", "swift", .number) == ["3.14"])
        #expect(texts("let x = 0xFF", "swift", .number) == ["0xFF"])
    }

    @Test("識別子の中の数字は数値として拾わない")
    func digitsInsideIdentifier() {
        #expect(texts("let utf8 = value2", "swift", .number).isEmpty)
    }

    // MARK: - 実際のコード

    @Test("Swift のコードがひととおり色分けされる")
    func realSwiftCode() {
        let code = """
        // トークン化する
        let tokenizer = MarkdownTokenizer()
        for token in tokenizer.tokenize("# 見出し") {
            print(token.kind, 42)
        }
        """
        #expect(texts(code, "swift", .comment) == ["// トークン化する"])
        #expect(texts(code, "swift", .keyword) == ["let", "for", "in"])
        // 中に "# を含むので、区切りの # を2つにする必要がある。
        #expect(texts(code, "swift", .string) == [##""# 見出し""##])
        #expect(texts(code, "swift", .number) == ["42"])
    }

    @Test("空のコードでも落ちない")
    func emptyCode() {
        #expect(tokens("", "swift").isEmpty)
        #expect(tokens("\n\n", "swift").isEmpty)
    }
}
