import Foundation
import Testing
@testable import MarkdownCore

@Suite("行の分割とブロック状態")
struct LineStateTests {

    @Test("改行の種類にかかわらず同じ行数に分かれる", arguments: ["\n", "\r\n", "\r"])
    func lineTerminators(terminator: String) {
        let source = "a\(terminator)b\(terminator)c"
        let lines = MarkdownTokenizer().tokenizeLines(source)
        #expect(lines.map { String(source[$0.range]) } == ["a", "b", "c"])
    }

    @Test("終端改行の後に空行は作られない")
    func trailingNewline() {
        let lines = MarkdownTokenizer().tokenizeLines("a\n")
        #expect(lines.count == 1)
    }

    @Test("空文字列でも1行として扱う")
    func emptySource() {
        let lines = MarkdownTokenizer().tokenizeLines("")
        #expect(lines.count == 1)
        #expect(lines[0].tokens.isEmpty)
        #expect(lines[0].stateAfter == .blank)
    }

    @Test("各行の stateAfter が次の行の stateBefore になる")
    func statesChainAcrossLines() {
        let source = """
        paragraph
        ```
        code
        ```

            indented
        """
        let lines = MarkdownTokenizer().tokenizeLines(source)
        #expect(lines.map(\.stateAfter) == [
            .paragraph,
            .fencedCode(marker: .backtick, length: 3),
            .fencedCode(marker: .backtick, length: 3),
            .blank,
            .blank,
            .indentedCode,
        ])
        for (previous, current) in zip(lines, lines.dropFirst()) {
            #expect(previous.stateAfter == current.stateBefore)
        }
    }

    @Test("1行だけを直前の状態から再解析できる")
    func tokenizeSingleLineFromState() {
        let source = "# not a heading here"
        let tokenizer = MarkdownTokenizer()
        let range = source.startIndex..<source.endIndex

        let asHeading = tokenizer.tokenizeLine(source, range: range, stateBefore: .blank)
        #expect(asHeading.tokens.contains { $0.kind == .heading(level: 1) })

        // フェンスが開いている状態から解析すれば、同じ行がコードになる。
        let asCode = tokenizer.tokenizeLine(
            source,
            range: range,
            stateBefore: .fencedCode(marker: .backtick, length: 3)
        )
        #expect(asCode.tokens.map(\.kind) == [.codeBlock])
        #expect(asCode.stateAfter == .fencedCode(marker: .backtick, length: 3))
    }

    @Test("tokenize は tokenizeLines を平坦化したものと一致する")
    func tokenizeMatchesLines() {
        let source = """
        # Title

        - **item**
        - [link](https://example.com)
        """
        let tokenizer = MarkdownTokenizer()
        #expect(tokenizer.tokenize(source) == tokenizer.tokenizeLines(source).flatMap(\.tokens))
    }

    @Test("nsRange は絵文字を含む文字列でも元の部分文字列を指す")
    func nsRangeWithEmoji() {
        let source = "# 🇯🇵 見出し"
        let text = source as NSString
        for token in MarkdownTokenizer().tokenize(source) {
            #expect(text.substring(with: token.nsRange(in: source)) == String(source[token.range]))
        }
    }

    @Test("トークンの範囲は行をはみ出さない")
    func tokensStayWithinTheirLine() {
        let source = """
        # Title with **bold**
        > quote with `code`
        1. item with [link](url)
        """
        for line in MarkdownTokenizer().tokenizeLines(source) {
            for token in line.tokens {
                #expect(token.range.lowerBound >= line.range.lowerBound)
                #expect(token.range.upperBound <= line.range.upperBound)
            }
        }
    }
}
