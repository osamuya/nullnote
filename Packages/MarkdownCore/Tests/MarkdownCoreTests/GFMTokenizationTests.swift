import Testing
@testable import MarkdownCore

@Suite("GFM 拡張")
struct GFMTokenizationTests {

    // MARK: - 取り消し線

    @Test("取り消し線", arguments: ["~", "~~"])
    func strikethrough(symbol: String) {
        #expect(MarkdownTokenizer.snapshot("\(symbol)gone\(symbol)") == [
            TokenSnapshot(.marker(.strikethrough), symbol),
            TokenSnapshot(.strikethrough, "gone"),
            TokenSnapshot(.marker(.strikethrough), symbol),
        ])
    }

    @Test("取り消し線の中の記法も解析される")
    func strikethroughWithInlineMarkup() {
        let tokens = MarkdownTokenizer.snapshot("~~**bold**~~")
        #expect(tokens.contains(TokenSnapshot(.strikethrough, "**bold**")))
        #expect(tokens.contains(TokenSnapshot(.strong, "bold")))
    }

    @Test("チルダ3個以上は取り消し線ではない")
    func tildeRunIsNotStrikethrough() {
        #expect(MarkdownTokenizer.snapshot("a ~~~b~~~ c").isEmpty)
    }

    @Test("行頭の ~~~ はコードフェンスのまま")
    func tildeFenceStillWorks() {
        let source = """
        ~~~
        code
        ~~~
        """
        #expect(MarkdownTokenizer.snapshot(source) == [
            TokenSnapshot(.marker(.codeFence), "~~~"),
            TokenSnapshot(.codeBlock, "code"),
            TokenSnapshot(.marker(.codeFence), "~~~"),
        ])
    }

    // MARK: - タスクリスト

    @Test("未完了のチェックボックス")
    func unchecked() {
        #expect(MarkdownTokenizer.snapshot("- [ ] todo") == [
            TokenSnapshot(.marker(.list), "-"),
            TokenSnapshot(.taskMarker(isChecked: false), "[ ]"),
        ])
    }

    @Test("完了したチェックボックス", arguments: ["x", "X"])
    func checked(mark: String) {
        #expect(MarkdownTokenizer.snapshot("- [\(mark)] done") == [
            TokenSnapshot(.marker(.list), "-"),
            TokenSnapshot(.taskMarker(isChecked: true), "[\(mark)]"),
        ])
    }

    @Test("番号付きリストでもチェックボックスは有効")
    func orderedTaskItem() {
        #expect(MarkdownTokenizer.snapshot("1. [x] done") == [
            TokenSnapshot(.marker(.list), "1."),
            TokenSnapshot(.taskMarker(isChecked: true), "[x]"),
        ])
    }

    @Test("チェックボックスの本文もインライン解析される")
    func taskItemContent() {
        let tokens = MarkdownTokenizer.snapshot("- [ ] **urgent**")
        #expect(tokens.contains(TokenSnapshot(.taskMarker(isChecked: false), "[ ]")))
        #expect(tokens.contains(TokenSnapshot(.strong, "urgent")))
    }

    @Test("空白でも x でもなければチェックボックスではない")
    func notATaskItem() {
        #expect(MarkdownTokenizer.snapshot("- [y] no") == [
            TokenSnapshot(.marker(.list), "-")
        ])
        // リストの外側では成立しない。
        #expect(MarkdownTokenizer.snapshot("[ ] no list").isEmpty)
    }

    // MARK: - 表

    @Test("表の基本形")
    func table() {
        let source = """
        | a | b |
        | - | - |
        | 1 | 2 |
        """
        #expect(MarkdownTokenizer.snapshot(source) == [
            TokenSnapshot(.marker(.tablePipe), "|"),
            TokenSnapshot(.tableHeaderCell, "a"),
            TokenSnapshot(.marker(.tablePipe), "|"),
            TokenSnapshot(.tableHeaderCell, "b"),
            TokenSnapshot(.marker(.tablePipe), "|"),

            TokenSnapshot(.marker(.tablePipe), "|"),
            TokenSnapshot(.tableDelimiterCell, "-"),
            TokenSnapshot(.marker(.tablePipe), "|"),
            TokenSnapshot(.tableDelimiterCell, "-"),
            TokenSnapshot(.marker(.tablePipe), "|"),

            TokenSnapshot(.marker(.tablePipe), "|"),
            TokenSnapshot(.tableCell, "1"),
            TokenSnapshot(.marker(.tablePipe), "|"),
            TokenSnapshot(.tableCell, "2"),
            TokenSnapshot(.marker(.tablePipe), "|"),
        ])
    }

    @Test("行頭・行末のパイプは省略できる")
    func tableWithoutOuterPipes() {
        let source = """
        a | b
        --- | ---
        1 | 2
        """
        let tokens = MarkdownTokenizer.snapshot(source)
        #expect(tokens.filter { $0.kind == .marker(.tablePipe) }.count == 3)
        #expect(tokens.contains(TokenSnapshot(.tableHeaderCell, "a")))
        #expect(tokens.contains(TokenSnapshot(.tableDelimiterCell, "---")))
        #expect(tokens.contains(TokenSnapshot(.tableCell, "2")))
    }

    @Test("配置指定つきの区切り行", arguments: [":-", "-:", ":-:", ":---:"])
    func alignedDelimiter(delimiter: String) {
        let source = "| a |\n| \(delimiter) |"
        #expect(MarkdownTokenizer.snapshot(source).contains(
            TokenSnapshot(.tableDelimiterCell, delimiter)
        ))
    }

    @Test("列数が一致しなければ表にならない")
    func columnCountMustMatch() {
        let source = """
        | a | b |
        | - |
        """
        let tokens = MarkdownTokenizer.snapshot(source)
        #expect(!tokens.contains { $0.kind == .tableHeaderCell })
        #expect(!tokens.contains { $0.kind == .marker(.tablePipe) })
    }

    @Test("区切り行が続かなければただの段落")
    func delimiterRowRequired() {
        #expect(MarkdownTokenizer.snapshot("| a | b |").isEmpty)
        #expect(MarkdownTokenizer.snapshot("a | b\nnot a delimiter").isEmpty)
    }

    @Test("セルの中の記法も解析される")
    func tableCellMarkup() {
        let source = """
        | **bold** |
        | --- |
        | `code` |
        """
        let tokens = MarkdownTokenizer.snapshot(source)
        #expect(tokens.contains(TokenSnapshot(.strong, "bold")))
        #expect(tokens.contains(TokenSnapshot(.inlineCode, "code")))
    }

    @Test("表は空行で終わる")
    func tableEndsAtBlankLine() {
        let source = """
        | a |
        | - |
        | 1 |

        | not | a | table |
        """
        let lines = MarkdownTokenizer().tokenizeLines(source)
        #expect(lines[2].stateAfter == .tableBody(columnCount: 1))
        #expect(lines[3].stateAfter == .blank)
        #expect(lines[4].tokens.isEmpty)
    }

    @Test("表は別のブロックの開始で終わる")
    func tableEndsAtNewBlock() {
        let source = """
        | a |
        | - |
        | 1 |
        # heading
        """
        let lines = MarkdownTokenizer().tokenizeLines(source)
        #expect(lines[3].tokens.map(\.kind) == [.marker(.heading), .heading(level: 1)])
    }

    @Test("エスケープされたパイプはセルを分割しない")
    func escapedPipe() {
        let source = """
        | a \\| b |
        | --- |
        """
        #expect(MarkdownTokenizer.lineSnapshots(source)[0] == [
            TokenSnapshot(.marker(.tablePipe), "|"),
            TokenSnapshot(.tableHeaderCell, #"a \| b"#),
            TokenSnapshot(.marker(.escape), #"\"#),
            TokenSnapshot(.escapedCharacter, "|"),
            TokenSnapshot(.marker(.tablePipe), "|"),
        ])
    }

    // MARK: - 拡張オートリンク

    @Test("山括弧の無い URL", arguments: [
        "https://example.com",
        "http://example.com/path?a=1",
        "www.example.com",
    ])
    func bareURL(url: String) {
        #expect(MarkdownTokenizer.snapshot(url) == [TokenSnapshot(.autolink, url)])
    }

    @Test("山括弧の無いメールアドレス")
    func bareEmail() {
        #expect(MarkdownTokenizer.snapshot("連絡は user@example.com まで") == [
            TokenSnapshot(.autolink, "user@example.com")
        ])
    }

    @Test("文末の句読点は URL に含めない")
    func trailingPunctuationExcluded() {
        #expect(MarkdownTokenizer.snapshot("See https://example.com.") == [
            TokenSnapshot(.autolink, "https://example.com")
        ])
        #expect(MarkdownTokenizer.snapshot("(see https://example.com)") == [
            TokenSnapshot(.autolink, "https://example.com")
        ])
    }

    @Test("対応の取れた括弧は URL に含める")
    func balancedParenthesesIncluded() {
        let url = "https://ja.wikipedia.org/wiki/Swift_(プログラミング言語)"
        #expect(MarkdownTokenizer.snapshot(url) == [TokenSnapshot(.autolink, url)])
    }

    @Test("単語の途中からは始まらない")
    func autolinkNeedsBoundary() {
        #expect(MarkdownTokenizer.snapshot("xhttps://example.com").isEmpty)
    }

    @Test("ドメインにドットが無ければリンクにしない")
    func domainNeedsDot() {
        #expect(MarkdownTokenizer.snapshot("http://localhost").isEmpty)
        #expect(MarkdownTokenizer.snapshot("a@b").isEmpty)
    }

    @Test("リンク先の URL は二重にトークン化しない")
    func urlInsideLinkDestination() {
        #expect(MarkdownTokenizer.snapshot("[x](https://example.com)") == [
            TokenSnapshot(.marker(.linkBracket), "["),
            TokenSnapshot(.linkText, "x"),
            TokenSnapshot(.marker(.linkBracket), "]"),
            TokenSnapshot(.marker(.linkParen), "("),
            TokenSnapshot(.linkURL, "https://example.com"),
            TokenSnapshot(.marker(.linkParen), ")"),
        ])
    }

    @Test("コードブロックの中の URL はリンクにしない")
    func urlInsideCodeSpan() {
        #expect(MarkdownTokenizer.snapshot("`https://example.com`") == [
            TokenSnapshot(.marker(.inlineCode), "`"),
            TokenSnapshot(.inlineCode, "https://example.com"),
            TokenSnapshot(.marker(.inlineCode), "`"),
        ])
    }
}
