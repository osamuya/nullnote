import Foundation
import Testing
@testable import NullnoteUI

@Suite("スクロール同期")
struct ScrollSyncTests {

    // MARK: - 行の索引

    @Test("行番号が引ける")
    func lineLookup() {
        let text = "one\ntwo\nthree"
        let index = LineIndex(text)
        #expect(index.lineCount == 3)
        #expect(index.line(atUTF16Offset: 0) == 1)   // "o" of one
        #expect(index.line(atUTF16Offset: 3) == 1)   // 行末の改行の手前
        #expect(index.line(atUTF16Offset: 4) == 2)   // "t" of two
        #expect(index.line(atUTF16Offset: 8) == 3)   // "t" of three
    }

    @Test("空文字列でも1行として扱う")
    func emptyText() {
        let index = LineIndex("")
        #expect(index.lineCount == 1)
        #expect(index.line(atUTF16Offset: 0) == 1)
    }

    @Test("末尾の改行の後ろは次の行になる")
    func trailingNewline() {
        let index = LineIndex("one\n")
        #expect(index.lineCount == 2)
        #expect(index.line(atUTF16Offset: 4) == 2)
    }

    @Test("UTF-16 で2つ分の文字があってもずれない")
    func surrogatePairs() {
        // 🇯🇵 は UTF-16 で4、絵文字1つで2。行頭の位置がずれないこと。
        let text = "🇯🇵 見出し\n本文"
        let index = LineIndex(text)
        let secondLineStart = text.utf16.distance(
            from: text.utf16.startIndex,
            to: text.range(of: "本文")!.lowerBound.samePosition(in: text.utf16)!
        )
        #expect(index.line(atUTF16Offset: secondLineStart) == 2)
        #expect(index.line(atUTF16Offset: secondLineStart - 1) == 1)
    }

    @Test("範囲外のオフセットでも落ちない")
    func outOfRange() {
        let index = LineIndex("one\ntwo")
        #expect(index.line(atUTF16Offset: -5) == 1)
        #expect(index.line(atUTF16Offset: 9999) == 2)
    }

    // MARK: - ブロックの行番号

    @Test("ブロックが元の行番号を持つ")
    func blocksCarrySourceLines() {
        let source = """
        # 見出し

        段落です。

        - 項目
        """
        let blocks = PreviewBuilder.build(source, theme: .standard())
        #expect(blocks.map(\.sourceLine) == [1, 3, 5])
    }

    @Test("行番号は昇順に並ぶ")
    func sourceLinesAreAscending() {
        let source = """
        # A

        > 引用

        ```swift
        let x = 1
        ```

        | a |
        | - |
        | 1 |

        最後の段落
        """
        let lines = PreviewBuilder.build(source, theme: .standard()).map(\.sourceLine)
        #expect(lines == lines.sorted())
        #expect(lines.first == 1)
    }

    // MARK: - 行からブロックへの対応付け

    @Test("その行から始まるブロックが選ばれる")
    func exactLineMatch() {
        let source = "# A\n\n段落\n\n- 項目"
        let blocks = PreviewBuilder.build(source, theme: .standard())
        #expect(blocks.blockID(containing: 1) == blocks[0].id)
        #expect(blocks.blockID(containing: 3) == blocks[1].id)
        #expect(blocks.blockID(containing: 5) == blocks[2].id)
    }

    @Test("ブロックの途中の行では、そのブロックの先頭に合わせる")
    func lineInsideBlock() {
        let source = """
        ```swift
        let a = 1
        let b = 2
        let c = 3
        ```

        次の段落
        """
        let blocks = PreviewBuilder.build(source, theme: .standard())
        // 2〜5行目はどれもコードブロックの中。先頭のブロックに寄せる。
        for line in 1...5 {
            #expect(blocks.blockID(containing: line) == blocks[0].id)
        }
        #expect(blocks.blockID(containing: 7) == blocks[1].id)
    }

    @Test("最終ブロックより後ろの行では最終ブロックのまま")
    func lineAfterLastBlock() {
        let blocks = PreviewBuilder.build("# A\n\n段落", theme: .standard())
        #expect(blocks.blockID(containing: 999) == blocks.last?.id)
    }

    @Test("先頭より前の行では先頭ブロックになる")
    func lineBeforeFirstBlock() {
        // 空行で始まる文書。最初のブロックは 2 行目から。
        let blocks = PreviewBuilder.build("\n# A", theme: .standard())
        #expect(blocks.blockID(containing: 1) == blocks.first?.id)
    }

    @Test("ブロックが無ければ対応先も無い")
    func noBlocks() {
        #expect([PreviewBlock]().blockID(containing: 1) == nil)
    }
}
