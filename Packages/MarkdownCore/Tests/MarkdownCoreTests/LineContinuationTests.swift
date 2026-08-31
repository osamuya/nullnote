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
