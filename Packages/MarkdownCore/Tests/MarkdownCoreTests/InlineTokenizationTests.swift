import Testing
@testable import MarkdownCore

@Suite("インライン記法")
struct InlineTokenizationTests {

    // MARK: - 強調

    @Test("強調", arguments: ["*", "_"])
    func emphasis(symbol: String) {
        #expect(MarkdownTokenizer.snapshot("\(symbol)italic\(symbol)") == [
            TokenSnapshot(.marker(.emphasis), symbol),
            TokenSnapshot(.emphasis, "italic"),
            TokenSnapshot(.marker(.emphasis), symbol),
        ])
    }

    @Test("強い強調", arguments: ["**", "__"])
    func strongEmphasis(symbol: String) {
        #expect(MarkdownTokenizer.snapshot("\(symbol)bold\(symbol)") == [
            TokenSnapshot(.marker(.strong), symbol),
            TokenSnapshot(.strong, "bold"),
            TokenSnapshot(.marker(.strong), symbol),
        ])
    }

    @Test("*** は強調と強い強調を重ねる")
    func strongAndEmphasis() {
        #expect(MarkdownTokenizer.snapshot("***both***") == [
            TokenSnapshot(.marker(.strong), "***"),
            TokenSnapshot(.strong, "both"),
            TokenSnapshot(.emphasis, "both"),
            TokenSnapshot(.marker(.strong), "***"),
        ])
    }

    @Test("強調の入れ子は外側から内側の順に並ぶ")
    func nestedEmphasis() {
        #expect(MarkdownTokenizer.snapshot("**bold *and italic***") == [
            TokenSnapshot(.marker(.strong), "**"),
            TokenSnapshot(.strong, "bold *and italic*"),
            TokenSnapshot(.marker(.strong), "**"),
            TokenSnapshot(.marker(.emphasis), "*"),
            TokenSnapshot(.emphasis, "and italic"),
            TokenSnapshot(.marker(.emphasis), "*"),
        ])
    }

    @Test("記号の直後が空白なら強調は始まらない")
    func emphasisRequiresAdjacentContent() {
        #expect(MarkdownTokenizer.snapshot("a * b * c").isEmpty)
    }

    @Test("アンダースコアは単語の途中では強調にならない")
    func underscoreInsideWord() {
        #expect(MarkdownTokenizer.snapshot("snake_case_name").isEmpty)
        #expect(MarkdownTokenizer.snapshot("a_b_c").isEmpty)
    }

    @Test("強調は行をまたがない")
    func emphasisDoesNotSpanLines() {
        #expect(MarkdownTokenizer.snapshot("*start\nend*").isEmpty)
    }

    // MARK: - インラインコード

    @Test("インラインコード")
    func inlineCode() {
        #expect(MarkdownTokenizer.snapshot("`let x = 1`") == [
            TokenSnapshot(.marker(.inlineCode), "`"),
            TokenSnapshot(.inlineCode, "let x = 1"),
            TokenSnapshot(.marker(.inlineCode), "`"),
        ])
    }

    @Test("バッククォートの数が一致する位置で閉じる")
    func inlineCodeWithBackticks() {
        #expect(MarkdownTokenizer.snapshot("``a ` b``") == [
            TokenSnapshot(.marker(.inlineCode), "``"),
            TokenSnapshot(.inlineCode, "a ` b"),
            TokenSnapshot(.marker(.inlineCode), "``"),
        ])
    }

    @Test("インラインコードの中の記号は記法として解釈されない")
    func inlineCodeSuppressesMarkup() {
        #expect(MarkdownTokenizer.snapshot("`a * b * c`") == [
            TokenSnapshot(.marker(.inlineCode), "`"),
            TokenSnapshot(.inlineCode, "a * b * c"),
            TokenSnapshot(.marker(.inlineCode), "`"),
        ])
    }

    @Test("強調の閉じ判定はインラインコードを飛び越える")
    func emphasisSkipsCodeSpan() {
        #expect(MarkdownTokenizer.snapshot("*a `*` b*") == [
            TokenSnapshot(.marker(.emphasis), "*"),
            TokenSnapshot(.emphasis, "a `*` b"),
            TokenSnapshot(.marker(.emphasis), "*"),
            TokenSnapshot(.marker(.inlineCode), "`"),
            TokenSnapshot(.inlineCode, "*"),
            TokenSnapshot(.marker(.inlineCode), "`"),
        ])
    }

    // MARK: - リンク・画像

    @Test("インラインリンク")
    func link() {
        #expect(MarkdownTokenizer.snapshot("[Apple](https://apple.com)") == [
            TokenSnapshot(.marker(.linkBracket), "["),
            TokenSnapshot(.linkText, "Apple"),
            TokenSnapshot(.marker(.linkBracket), "]"),
            TokenSnapshot(.marker(.linkParen), "("),
            TokenSnapshot(.linkURL, "https://apple.com"),
            TokenSnapshot(.marker(.linkParen), ")"),
        ])
    }

    @Test("画像は ![ をマーカーに含める")
    func image() {
        let tokens = MarkdownTokenizer.snapshot("![alt](a.png)")
        #expect(tokens.first == TokenSnapshot(.marker(.linkBracket), "!["))
        #expect(tokens.contains(TokenSnapshot(.linkURL, "a.png")))
    }

    @Test("リンクテキストの中の記法も解析される")
    func linkTextMarkup() {
        let tokens = MarkdownTokenizer.snapshot("[**bold**](x)")
        #expect(tokens.contains(TokenSnapshot(.linkText, "**bold**")))
        #expect(tokens.contains(TokenSnapshot(.strong, "bold")))
    }

    @Test("] の直後に ( が無ければリンクではない")
    func notALink() {
        #expect(MarkdownTokenizer.snapshot("[just brackets]").isEmpty)
        #expect(MarkdownTokenizer.snapshot("[ref][id]").isEmpty)
    }

    // MARK: - オートリンク

    @Test("オートリンク", arguments: ["https://example.com", "user@example.com"])
    func autolink(target: String) {
        #expect(MarkdownTokenizer.snapshot("<\(target)>") == [
            TokenSnapshot(.marker(.autolinkAngle), "<"),
            TokenSnapshot(.autolink, target),
            TokenSnapshot(.marker(.autolinkAngle), ">"),
        ])
    }

    @Test("スキームもアットマークも無ければオートリンクではない")
    func notAnAutolink() {
        #expect(MarkdownTokenizer.snapshot("<br>").isEmpty)
        #expect(MarkdownTokenizer.snapshot("<not a link>").isEmpty)
    }

    // MARK: - エスケープ

    @Test("バックスラッシュでエスケープされた記号は記法にならない")
    func escapedPunctuation() {
        #expect(MarkdownTokenizer.snapshot(#"\*not emphasis\*"#) == [
            TokenSnapshot(.marker(.escape), #"\"#),
            TokenSnapshot(.escapedCharacter, "*"),
            TokenSnapshot(.marker(.escape), #"\"#),
            TokenSnapshot(.escapedCharacter, "*"),
        ])
    }

    @Test("記号以外の前のバックスラッシュはただの文字")
    func backslashBeforeLetter() {
        #expect(MarkdownTokenizer.snapshot(#"\n"#).isEmpty)
    }
}
