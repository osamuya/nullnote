import Testing
@testable import MarkdownCore

@Suite("改行で行頭の印を継ぐ")
struct LineContinuationTests {

    /// 行末で改行したときの判断。いちばん多い使い方。
    private func atEnd(_ line: String, inCode: Bool = false) -> LineContinuation {
        LineContinuationRule.decide(
            line: line, caretUTF16Offset: line.utf16.count, isInsideCode: inCode
        )
    }

    /// 後ろに閉じになりうるフェンス行がある状態。
    private func ahead(_ line: String) -> LineContinuation {
        LineContinuationRule.decide(
            line: line, caretUTF16Offset: line.utf16.count, hasClosingFenceAhead: true
        )
    }

    // MARK: - 継ぐ

    @Test("箇条書きは同じ印を継ぐ")
    func bullet() {
        #expect(atEnd("- りんご") == .carry("- "))
        #expect(atEnd("* りんご") == .carry("* "))
        #expect(atEnd("+ りんご") == .carry("+ "))
    }

    @Test("順序つきは番号を 1 に寄せ、区切り文字は引き継ぐ")
    func ordered() {
        #expect(atEnd("1. りんご") == .carry("1. "))
        #expect(atEnd("7. りんご") == .carry("1. "))
        #expect(atEnd("1) りんご") == .carry("1) "))
        #expect(atEnd("42) りんご") == .carry("1) "))
    }

    @Test("インデントはそのまま継ぐ")
    func indent() {
        #expect(atEnd("  - りんご") == .carry("  - "))
        #expect(atEnd("\t- りんご") == .carry("\t- "))
        #expect(atEnd("    1. りんご") == .carry("    1. "))
    }

    @Test("タスクリストは `- ` だけ継ぐ")
    func task() {
        #expect(atEnd("- [ ] やること") == .carry("- "))
        #expect(atEnd("- [x] やった") == .carry("- "))
    }

    @Test("印と本文のあいだの空白が広くても、継ぐのは空白ひとつ")
    func extraSpaces() {
        #expect(atEnd("-    りんご") == .carry("- "))
    }

    // MARK: - 引用

    @Test("引用は `> ` を継ぐ")
    func quote() {
        #expect(atEnd("> 引用") == .carry("> "))
    }

    @Test("`>` の後ろに空白が無くても、継ぐときは空白を補う")
    func quoteWithoutSpace() {
        #expect(atEnd(">引用") == .carry("> "))
    }

    @Test("入れ子の引用は深さごと継ぐ")
    func nestedQuote() {
        #expect(atEnd(">> 深い") == .carry(">> "))
        #expect(atEnd("> > 深い") == .carry("> > "))
        #expect(atEnd(">>> もっと深い") == .carry(">>> "))
    }

    @Test("引用の中のリストは、両方継ぐ")
    func quotedList() {
        #expect(atEnd("> - りんご") == .carry("> - "))
        #expect(atEnd("> 1. りんご") == .carry("> 1. "))
        #expect(atEnd(">> - 深いリスト") == .carry(">> - "))
    }

    @Test("引用のインデントもそのまま継ぐ")
    func indentedQuote() {
        #expect(atEnd("  > 引用") == .carry("  > "))
    }

    // MARK: - コードフェンス

    @Test("フェンスを開いたら、閉じを置く")
    func openFence() {
        #expect(atEnd("```") == .openFence(closing: "```"))
        #expect(atEnd("```bash") == .openFence(closing: "```"))
        #expect(atEnd("```swift") == .openFence(closing: "```"))
    }

    @Test("記号と長さは開いたものに合わせる")
    func fenceShape() {
        #expect(atEnd("~~~") == .openFence(closing: "~~~"))
        #expect(atEnd("~~~yaml") == .openFence(closing: "~~~"))
        #expect(atEnd("````") == .openFence(closing: "````"))
    }

    @Test("後ろに閉じがあれば足さない")
    func alreadyClosed() {
        #expect(ahead("```bash") == .plain)
        #expect(ahead("```") == .plain)
    }

    @Test("コードブロックの中のフェンス行は閉じなので、何もしない")
    func closingFenceDoesNothing() {
        #expect(atEnd("```", inCode: true) == .plain)
    }

    @Test("行の途中では閉じを足さない（言語名を打っている最中かもしれない）")
    func caretInTheMiddleOfFence() {
        #expect(LineContinuationRule.decide(line: "```bash", caretUTF16Offset: 3) == .plain)
    }

    @Test("バッククォート3つに満たなければフェンスではない")
    func tooShort() {
        #expect(atEnd("``") == .plain)
        #expect(atEnd("`code`") == .plain)
    }

    @Test("閉じフェンスの判定に言語名は許さない")
    func closingFenceHasNoInfoString() {
        // 閉じになる
        #expect(LineContinuationRule.closesFence("```", marker: "`", minimumLength: 3))
        #expect(LineContinuationRule.closesFence("````", marker: "`", minimumLength: 3))
        #expect(LineContinuationRule.closesFence("  ```", marker: "`", minimumLength: 3))
        // 閉じにならない
        #expect(!LineContinuationRule.closesFence("```swift", marker: "`", minimumLength: 3))
        #expect(!LineContinuationRule.closesFence("``", marker: "`", minimumLength: 3))
        #expect(!LineContinuationRule.closesFence("~~~", marker: "`", minimumLength: 3))
        // 開いた方が長ければ、短い閉じでは閉じない
        #expect(!LineContinuationRule.closesFence("```", marker: "`", minimumLength: 4))
    }

    @Test("開始フェンスの記号と長さを取り出せる")
    func openingShape() {
        #expect(LineContinuationRule.openingFenceShape(of: "```bash")?.marker == "`")
        #expect(LineContinuationRule.openingFenceShape(of: "````")?.length == 4)
        #expect(LineContinuationRule.openingFenceShape(of: "~~~")?.marker == "~")
        #expect(LineContinuationRule.openingFenceShape(of: "ふつうの行") == nil)
    }

    // MARK: - 表

    /// 表の状態を指定して、行末で改行したときの判断。
    private func table(_ line: String, state: MarkdownBlockState) -> LineContinuation {
        LineContinuationRule.decide(
            line: line, caretUTF16Offset: line.utf16.count, blockState: state
        )
    }

    @Test("見出し行なら、区切り行と空の行を置く")
    func header() {
        #expect(table("| 名前 | 値 |", state: .blank)
                == .tableRow(lines: ["|---|---|", "|  |  |"], caretInFirstCellOf: 1))
    }

    @Test("列が増えれば、区切りも空の行も増える")
    func columns() {
        #expect(table("| a | b | c |", state: .blank)
                == .tableRow(lines: ["|---|---|---|", "|  |  |  |"], caretInFirstCellOf: 1))
    }

    @Test("本体の行なら、空の行だけ置く")
    func body() {
        #expect(table("| りんご | 100 |", state: .tableBody(columnCount: 2))
                == .tableRow(lines: ["|  |  |"], caretInFirstCellOf: 0))
    }

    @Test("区切り行の上でも、次は本体の行")
    func afterDelimiter() {
        #expect(table("|---|---|", state: .tableDelimiterExpected(columnCount: 2))
                == .tableRow(lines: ["|  |  |"], caretInFirstCellOf: 0))
    }

    @Test("中身が空の行で改行すると、表から抜ける")
    func endTable() {
        #expect(table("|  |  |", state: .tableBody(columnCount: 2)) == .end(clearing: 7))
    }

    @Test("パイプが無ければ表ではない")
    func notATable() {
        #expect(table("ふつうの段落", state: .blank) == .plain)
    }

    @Test("コードブロックの中の `|` は表ではない")
    func pipeInsideCode() {
        #expect(LineContinuationRule.decide(
            line: "| a | b |", caretUTF16Offset: 9, isInsideCode: true) == .plain)
    }

    // MARK: - 抜ける

    @Test("中身が空の項目で改行すると、印を消して抜ける")
    func endList() {
        #expect(atEnd("- ") == .end(clearing: 2))
        #expect(atEnd("-") == .end(clearing: 1))
        #expect(atEnd("1. ") == .end(clearing: 3))
        #expect(atEnd("  - ") == .end(clearing: 4))
    }

    @Test("引用の印だけの行で改行すると、抜ける")
    func endQuote() {
        #expect(atEnd("> ") == .end(clearing: 2))
        #expect(atEnd(">") == .end(clearing: 1))
        #expect(atEnd(">> ") == .end(clearing: 3))
    }

    @Test("引用とリストが重なっていたら、まとめて消す")
    func endQuotedList() {
        #expect(atEnd("> - ") == .end(clearing: 4))
    }

    @Test("タスクの `[ ]` は本文なので、空とは見なさない")
    func emptyTaskIsNotEmpty() {
        #expect(atEnd("- [ ] ") == .carry("- "))
    }

    // MARK: - 継がない

    @Test("リストでない行は何もしない")
    func notAList() {
        #expect(atEnd("ふつうの段落") == .plain)
        #expect(atEnd("# 見出し") == .plain)
        #expect(atEnd("") == .plain)
    }

    @Test("強調をリストと取り違えない")
    func emphasisIsNotAList() {
        #expect(atEnd("*強調*") == .plain)
    }

    @Test("コードブロックの中では何もしない")
    func insideCode() {
        #expect(atEnd("- rf", inCode: true) == .plain)
        #expect(atEnd("1. step", inCode: true) == .plain)
        #expect(atEnd("> redirect", inCode: true) == .plain)
    }

    // MARK: - カーソルの位置

    @Test("本文の途中で改行すると、続きにも印が付く")
    func splitInTheMiddle() {
        // 「- りんごとみかん」の「ご」の後ろ
        let line = "- りんごとみかん"
        #expect(LineContinuationRule.decide(line: line, caretUTF16Offset: 5)
                == .carry("- "))
    }

    @Test("印の中にカーソルがあるときは、継がない")
    func caretInsideMarker() {
        // 「- りんご」の `-` の直後（空白の前）
        #expect(LineContinuationRule.decide(line: "- りんご", caretUTF16Offset: 1) == .plain)
        #expect(LineContinuationRule.decide(line: "- りんご", caretUTF16Offset: 0) == .plain)
        // 「12. りんご」の数字のあいだ
        #expect(LineContinuationRule.decide(line: "12. りんご", caretUTF16Offset: 2) == .plain)
    }

    @Test("空の項目でも、カーソルが行末になければ抜けない")
    func emptyButCaretNotAtEnd() {
        // 「-  」の真ん中。後ろに空白が残っている
        #expect(LineContinuationRule.decide(line: "-  ", caretUTF16Offset: 2) == .plain)
    }
}
