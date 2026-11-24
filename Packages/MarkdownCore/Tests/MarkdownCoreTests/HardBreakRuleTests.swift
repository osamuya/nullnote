import Testing
@testable import MarkdownCore

/// 改行のときに行末へ半角スペース2つを入れるか（#015・D-79）。
@Suite("改行で行末に空白2つを入れる")
struct HardBreakRuleTests {

    /// 行末で改行したとき。`LineContinuationRule` の判断もいっしょに通す。
    private func atEnd(
        _ line: String, state: MarkdownBlockState = .blank, inCode: Bool = false
    ) -> String {
        at(line, caret: line.utf16.count, state: state, inCode: inCode)
    }

    private func at(
        _ line: String, caret: Int, state: MarkdownBlockState = .blank, inCode: Bool = false
    ) -> String {
        let continuation = LineContinuationRule.decide(
            line: line, caretUTF16Offset: caret, isInsideCode: inCode, blockState: state
        )
        return HardBreakRule.spaces(
            line: line, caretUTF16Offset: caret, continuation: continuation,
            isInsideCode: inCode, blockState: state
        )
    }

    // MARK: - 入れる

    @Test("文字のある普通の行には入れる")
    func plainLine() {
        #expect(atEnd("一行目の文です。") == "  ")
        #expect(atEnd("続きの行", state: .paragraph) == "  ")
    }

    @Test("行の途中で押したときも、カーソルの前に入れる")
    func middleOfLine() {
        #expect(at("前半後半", caret: 2) == "  ")
    }

    @Test("引用の行には入れる")
    func quote() {
        #expect(atEnd("> 引用の文") == "  ")
        #expect(atEnd(">> 入れ子の引用") == "  ")
    }

    @Test("行末の空白が1つなら、1つだけ足して2つにする")
    func oneTrailingSpace() {
        #expect(atEnd("文 ") == " ")
    }

    @Test("リストの項目の下の、字下げした続きの行には入れる")
    func indentedContinuation() {
        #expect(atEnd("    項目の続き", state: .paragraph) == "  ")
    }

    // MARK: - 入れない

    @Test("リストの行には入れない。次の行は新しい項目になる")
    func listItem() {
        #expect(atEnd("- 項目") == "")
        #expect(atEnd("1. 一番目") == "")
        #expect(atEnd("- [ ] やること") == "")
        #expect(atEnd("  * 入れ子") == "")
        #expect(atEnd("> - 引用の中のリスト") == "")
        #expect(at("- 項目の途中", caret: 4) == "")
    }

    @Test("空の行・空白だけの行には入れない")
    func emptyLine() {
        #expect(atEnd("") == "")
        #expect(atEnd("   ") == "")
        #expect(at("　文", caret: 0) == "")
    }

    @Test("見出し・水平線・コードフェンスの行には入れない")
    func otherBlocks() {
        #expect(atEnd("# 見出し") == "")
        #expect(atEnd("---") == "")
        #expect(atEnd("```swift") == "")
    }

    @Test("コードブロックの中には入れない")
    func insideCode() {
        #expect(atEnd("let a = 1", state: .fencedCode(marker: .backtick, length: 3), inCode: true) == "")
        #expect(atEnd("    let a = 1") == "")
    }

    @Test("表の行には入れない")
    func table() {
        #expect(atEnd("| 名前 | 値 |") == "")
        #expect(atEnd("| りんご | 100 |", state: .tableBody(columnCount: 2)) == "")
        #expect(at("| りんご | 100 |", caret: 4, state: .tableBody(columnCount: 2)) == "")
    }

    @Test("コメントの中には入れない")
    func insideComment() {
        #expect(atEnd("メモ", state: .htmlComment(insideParagraph: false)) == "")
    }

    @Test("すでに改行の印がある行には足さない")
    func alreadyBroken() {
        #expect(atEnd("文  ") == "")
        #expect(atEnd("文   ") == "")
        #expect(atEnd("文\\") == "")
    }

    @Test("リストから抜ける改行には入れない")
    func endingList() {
        #expect(atEnd("- ") == "")
        #expect(atEnd("> ") == "")
    }
}
