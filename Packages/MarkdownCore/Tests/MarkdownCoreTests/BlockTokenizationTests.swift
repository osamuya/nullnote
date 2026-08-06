import Testing
@testable import MarkdownCore

@Suite("ブロック記法")
struct BlockTokenizationTests {

    // MARK: - 見出し

    @Test("ATX 見出しはマーカーと本文に分かれる")
    func atxHeading() {
        #expect(MarkdownTokenizer.snapshot("# Title") == [
            TokenSnapshot(.marker(.heading), "#"),
            TokenSnapshot(.heading(level: 1), "Title"),
        ])
    }

    @Test("見出しレベルは # の数で決まる")
    func headingLevels() {
        for level in 1...6 {
            let source = String(repeating: "#", count: level) + " H"
            #expect(MarkdownTokenizer.snapshot(source) == [
                TokenSnapshot(.marker(.heading), String(repeating: "#", count: level)),
                TokenSnapshot(.heading(level: level), "H"),
            ])
        }
    }

    @Test("# が7個以上、または直後に空白が無い行は見出しではない")
    func notAHeading() {
        #expect(MarkdownTokenizer.snapshot("####### too deep").isEmpty)
        #expect(MarkdownTokenizer.snapshot("#hashtag").isEmpty)
    }

    @Test("末尾の閉じシーケンスはマーカーとして扱う")
    func headingClosingSequence() {
        #expect(MarkdownTokenizer.snapshot("### Title ###") == [
            TokenSnapshot(.marker(.heading), "###"),
            TokenSnapshot(.heading(level: 3), "Title"),
            TokenSnapshot(.marker(.heading), "###"),
        ])
    }

    @Test("見出しの中のインライン記法も解析される")
    func headingWithInlineMarkup() {
        #expect(MarkdownTokenizer.snapshot("# **bold**") == [
            TokenSnapshot(.marker(.heading), "#"),
            TokenSnapshot(.heading(level: 1), "**bold**"),
            TokenSnapshot(.marker(.strong), "**"),
            TokenSnapshot(.strong, "bold"),
            TokenSnapshot(.marker(.strong), "**"),
        ])
    }

    // MARK: - 水平線

    @Test("水平線", arguments: ["---", "***", "___", "- - -", "-----"])
    func thematicBreak(source: String) {
        #expect(MarkdownTokenizer.snapshot(source) == [
            TokenSnapshot(.marker(.thematicBreak), source)
        ])
    }

    @Test("記号が2個以下なら水平線ではない")
    func notAThematicBreak() {
        #expect(MarkdownTokenizer.snapshot("--").isEmpty)
    }

    // MARK: - リスト

    @Test("箇条書きマーカー", arguments: ["-", "*", "+"])
    func bulletList(symbol: String) {
        #expect(MarkdownTokenizer.snapshot("\(symbol) item") == [
            TokenSnapshot(.marker(.list), symbol)
        ])
    }

    @Test("番号付きリストマーカー", arguments: ["1.", "42)"])
    func orderedList(marker: String) {
        #expect(MarkdownTokenizer.snapshot("\(marker) item") == [
            TokenSnapshot(.marker(.list), marker)
        ])
    }

    @Test("マーカーの直後に空白が無ければリストではない")
    func notAList() {
        #expect(MarkdownTokenizer.snapshot("1.item").isEmpty)
        // 行頭の "*" は強調の開始として扱われる。
        #expect(MarkdownTokenizer.snapshot("*emphasis*") == [
            TokenSnapshot(.marker(.emphasis), "*"),
            TokenSnapshot(.emphasis, "emphasis"),
            TokenSnapshot(.marker(.emphasis), "*"),
        ])
    }

    @Test("リスト項目の本文もインライン解析される")
    func listItemContent() {
        #expect(MarkdownTokenizer.snapshot("- `code`") == [
            TokenSnapshot(.marker(.list), "-"),
            TokenSnapshot(.marker(.inlineCode), "`"),
            TokenSnapshot(.inlineCode, "code"),
            TokenSnapshot(.marker(.inlineCode), "`"),
        ])
    }

    // MARK: - 引用

    @Test("引用はマーカーと本文に分かれる")
    func blockQuote() {
        #expect(MarkdownTokenizer.snapshot("> quoted") == [
            TokenSnapshot(.marker(.blockQuote), "> "),
            TokenSnapshot(.blockQuote, "quoted"),
        ])
    }

    @Test("引用の中の見出しも解析される")
    func blockQuoteWithHeading() {
        #expect(MarkdownTokenizer.snapshot("> # Title") == [
            TokenSnapshot(.marker(.blockQuote), "> "),
            TokenSnapshot(.blockQuote, "# Title"),
            TokenSnapshot(.marker(.heading), "#"),
            TokenSnapshot(.heading(level: 1), "Title"),
        ])
    }

    @Test("引用のネスト")
    func nestedBlockQuote() {
        #expect(MarkdownTokenizer.snapshot(">> deep") == [
            TokenSnapshot(.marker(.blockQuote), ">"),
            TokenSnapshot(.blockQuote, "> deep"),
            TokenSnapshot(.marker(.blockQuote), "> "),
            TokenSnapshot(.blockQuote, "deep"),
        ])
    }

    // MARK: - コードブロック

    @Test("フェンス付きコードブロック")
    func fencedCodeBlock() {
        let source = """
        ```swift
        let x = 1
        ```
        """
        #expect(MarkdownTokenizer.snapshot(source) == [
            TokenSnapshot(.marker(.codeFence), "```"),
            TokenSnapshot(.codeLanguage, "swift"),
            TokenSnapshot(.codeBlock, "let x = 1"),
            TokenSnapshot(.marker(.codeFence), "```"),
        ])
    }

    @Test("フェンス内では他の記法が無効になる")
    func fencedCodeSuppressesMarkup() {
        let source = """
        ~~~
        # not a heading
        ~~~
        """
        #expect(MarkdownTokenizer.snapshot(source) == [
            TokenSnapshot(.marker(.codeFence), "~~~"),
            TokenSnapshot(.codeBlock, "# not a heading"),
            TokenSnapshot(.marker(.codeFence), "~~~"),
        ])
    }

    @Test("閉じフェンスは開始と同じ記号で、同じ長さ以上でなければならない")
    func fenceRequiresMatchingMarker() {
        let source = """
        ````
        ```
        still code
        """
        #expect(MarkdownTokenizer.snapshot(source) == [
            TokenSnapshot(.marker(.codeFence), "````"),
            TokenSnapshot(.codeBlock, "```"),
            TokenSnapshot(.codeBlock, "still code"),
        ])
    }

    @Test("空行の後の4スペースインデントはコードブロック")
    func indentedCodeBlock() {
        let source = "\n    let x = 1\n    let y = 2"
        #expect(MarkdownTokenizer.snapshot(source) == [
            TokenSnapshot(.codeBlock, "    let x = 1"),
            TokenSnapshot(.codeBlock, "    let y = 2"),
        ])
    }

    @Test("段落の途中の4スペースインデントはコードブロックにならない")
    func indentedContinuationIsNotCode() {
        let source = "paragraph\n    # still a paragraph"
        #expect(MarkdownTokenizer.snapshot(source).isEmpty)
    }
}
