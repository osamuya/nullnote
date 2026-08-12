import CoreGraphics
import Testing
@testable import NullnoteUI

/// ブロックとブロックのあいだの間隔。
///
/// 具体的な数値ではなく、**大小の関係**を縛る。
/// 見た目の調整で数値は動くが、「段落どうしより、表やコードの前の方が空く」
/// 「見出しの前がいちばん空く」という関係が崩れると、文書の構造が読めなくなる。
@Suite("プレビューのブロック間隔")
struct PreviewSpacingTests {

    let fontSize: CGFloat = 14

    func blocks(_ source: String) -> [PreviewBlock] {
        PreviewBuilder.build(source, theme: .standard(fontSize: 14))
    }

    /// `source` の n 番目のブロックの上に空く量。
    func gap(_ source: String, at index: Int) -> CGFloat {
        let blocks = blocks(source)
        guard blocks.indices.contains(index) else {
            Issue.record("ブロックが足りない: \(blocks.count) 個")
            return 0
        }
        return PreviewSpacing.gap(
            before: blocks[index],
            after: index > 0 ? blocks[index - 1] : nil,
            fontSize: fontSize
        )
    }

    @Test("先頭のブロックの上は空けない")
    func firstBlockHasNoGap() {
        // 外周の余白があるので、ここで足すと上だけ広くなる。
        #expect(gap("本文\n", at: 0) == 0)
    }

    @Test("段落どうしより、重いブロックの前の方が空く")
    func heavyBlocksGetMoreRoom() {
        let betweenParagraphs = gap("あ\n\nい\n", at: 1)
        for source in [
            "あ\n\n```\nコード\n```\n",
            "あ\n\n| 見出し |\n|---|\n| 値 |\n",
            "あ\n\n- 項目\n",
            "あ\n\n> 引用\n",
        ] {
            #expect(gap(source, at: 1) > betweenParagraphs, "\(source) の前が段落並みしか空いていない")
        }
    }

    @Test("重いブロックの後ろも空く")
    func heavyBlocksPushTheNextBlock() {
        // 表のすぐ下に本文が貼り付くと、表の一部に見える。
        let betweenParagraphs = gap("あ\n\nい\n", at: 1)
        #expect(gap("| 見出し |\n|---|\n| 値 |\n\nあとの本文\n", at: 1) > betweenParagraphs)
        #expect(gap("```\nコード\n```\n\nあとの本文\n", at: 1) > betweenParagraphs)
    }

    @Test("見出しの前がいちばん空く")
    func headingsGetTheMostRoom() {
        let beforeTable = gap("あ\n\n| 見出し |\n|---|\n| 値 |\n", at: 1)
        #expect(gap("あ\n\n# 見出し\n", at: 1) > beforeTable)
        #expect(gap("あ\n\n## 見出し\n", at: 1) > beforeTable)
    }

    @Test("浅い見出しほど大きく空ける")
    func shallowHeadingsGetMoreRoom() {
        #expect(gap("あ\n\n## 見出し\n", at: 1) > gap("あ\n\n#### 見出し\n", at: 1))
    }

    @Test("見出しの下は本文と近づける")
    func headingHugsItsBody() {
        // 見出しは次の話の始まり。上より下を詰めないと、どちらに属すか分からない。
        #expect(gap("# 見出し\n\n本文\n", at: 1) < gap("本文\n\n# 見出し\n", at: 1))
    }

    @Test("重いブロックが続いても足し算にならない")
    func adjacentHeavyBlocksDoNotStack() {
        // 前の「下」と次の「上」を足すと、表とリストが続いたときだけ極端に空く。
        let tableThenList = gap("| 見出し |\n|---|\n| 値 |\n\n- 項目\n", at: 1)
        let paragraphThenList = gap("あ\n\n- 項目\n", at: 1)
        #expect(tableThenList == paragraphThenList)
    }

    @Test("文字サイズに比例する")
    func scalesWithFontSize() {
        let blocks = blocks("あ\n\n# 見出し\n")
        let small = PreviewSpacing.gap(before: blocks[1], after: blocks[0], fontSize: 10)
        let large = PreviewSpacing.gap(before: blocks[1], after: blocks[0], fontSize: 20)
        #expect(large == small * 2)
    }
}
