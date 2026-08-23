import Testing
@testable import MarkdownCore

/// 空行に見えるのに、空行にならない行。
///
/// CommonMark の「空行」は**半角スペースとタブだけの行**を指す。
/// 全角スペースが1つ残っていると段落が途切れず、直後の `-----` が
/// 水平線ではなく**見出しの下線**として働いて、本文が丸ごと見出しに化ける（B-18）。
///
/// 目で見つけられないので、印を付けられることをここで縛る。
@Suite("空行に見えて空でない行")
struct InvisibleWhitespaceTests {

    @Test("全角スペースだけの行には印が付く")
    func fullWidthSpaceOnly() {
        #expect(MarkdownTokenizer.snapshot("　") == [
            TokenSnapshot(.invisibleWhitespace, "　")
        ])
    }

    @Test("ノーブレークスペースだけの行にも印が付く")
    func noBreakSpaceOnly() {
        #expect(MarkdownTokenizer.snapshot("\u{00A0}") == [
            TokenSnapshot(.invisibleWhitespace, "\u{00A0}")
        ])
    }

    @Test("半角スペースやタブが混じっていても、全角があれば印が付く")
    func mixedWithHalfWidth() {
        #expect(MarkdownTokenizer.snapshot(" 　\t") == [
            TokenSnapshot(.invisibleWhitespace, " 　\t")
        ])
    }

    @Test("本当に空の行には何も出ない")
    func trulyEmptyLine() {
        #expect(MarkdownTokenizer.snapshot("").isEmpty)
        #expect(MarkdownTokenizer.snapshot("\n\n").isEmpty)
    }

    @Test("半角スペースやタブだけの行には印を付けない", arguments: [" ", "   ", "\t", " \t "])
    func halfWidthOnlyIsReallyBlank(source: String) {
        // これらは本当に空行になる。段落は切れるので、驚くことは起きない。
        #expect(MarkdownTokenizer.snapshot(source).isEmpty)
    }

    @Test("段落の頭の字下げには印を付けない")
    func paragraphIndentIsLeftAlone() {
        // 日本語の字下げはこの形で書く。ここに印を出すと本文が読みづらくなる。
        #expect(MarkdownTokenizer.snapshot("　本文です。").isEmpty)
    }

    @Test("印を付けても、行の意味は変えない")
    func doesNotChangeMeaning() {
        // 印は表示のためだけのもの。段落が途切れないという CommonMark の解釈は
        // そのまま残す。ここを変えると、エディタとプレビューがずれる。
        let lines = MarkdownTokenizer().tokenizeLines("本文\n　\n-----\n")
        #expect(lines[1].stateAfter == .paragraph, "印を付けたせいで段落が切れている")
    }

    @Test("本当の空行なら、そのあとは空行として続く")
    func realBlankLineEndsParagraph() {
        let lines = MarkdownTokenizer().tokenizeLines("本文\n\n-----\n")
        #expect(lines[1].stateAfter == .blank)
    }
}
