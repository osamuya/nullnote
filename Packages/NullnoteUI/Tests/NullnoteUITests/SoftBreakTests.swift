import Foundation
import Testing
@testable import NullnoteUI

/// 普通の改行をどう見せるか（D-33）。
///
/// 既定は CommonMark どおり、ひと続きの行として畳む。
/// 設定を入れた人にだけ、書いたとおりの位置で折る。**本文は書き換えない。**
@Suite("普通の改行の見せ方")
struct SoftBreakTests {

    func paragraph(_ source: String, newlineStyle: NewlineStyle) -> String? {
        let blocks = PreviewBuilder.build(
            source, theme: .standard(), newlineStyle: newlineStyle
        )
        guard case .paragraph(let text) = blocks.first?.content else { return nil }
        return String(text.characters)
    }

    @Test("既定では、普通の改行はスペースに畳まれる")
    func softBreakFoldsByDefault() {
        #expect(paragraph("あ\nい", newlineStyle: .markdown) == "あ い")
    }

    @Test("設定を入れると、普通の改行がそのまま改行になる")
    func softBreakBecomesLineBreak() {
        #expect(paragraph("あ\nい", newlineStyle: .lineBreak) == "あ\nい")
    }

    @Test("半角スペース2つの改行は、どちらの設定でも改行のまま")
    func hardBreakIsAlwaysBreak() {
        #expect(paragraph("あ  \nい", newlineStyle: .markdown) == "あ\nい")
        #expect(paragraph("あ  \nい", newlineStyle: .lineBreak) == "あ\nい")
    }

    @Test("空行で区切った段落は、設定に関わらず別のブロックのまま")
    func blankLineStillSplitsParagraphs() {
        for style in NewlineStyle.allCases {
            let blocks = PreviewBuilder.build(
                "あ\n\nい", theme: .standard(), newlineStyle: style
            )
            #expect(blocks.count == 2)
        }
    }

    @Test("リストや引用の中でも同じ扱いになる")
    func insideListAndQuote() {
        let list = PreviewBuilder.build(
            "- あ\n  い", theme: .standard(), newlineStyle: .lineBreak
        )
        guard case .list(let items) = list.first?.content,
              case .paragraph(let text) = items.items.first?.blocks.first?.content
        else {
            Issue.record("リストが取れていない")
            return
        }
        #expect(String(text.characters) == "あ\nい")

        let quote = PreviewBuilder.build(
            "> あ\n> い", theme: .standard(), newlineStyle: .lineBreak
        )
        guard case .quote(let blocks) = quote.first?.content,
              case .paragraph(let quoted) = blocks.first?.content
        else {
            Issue.record("引用が取れていない")
            return
        }
        #expect(String(quoted.characters) == "あ\nい")
    }

    @Test("設定を入れても、画像だけの段落は絵のまま")
    func imagesOnlyParagraphIsUnaffected() {
        let blocks = PreviewBuilder.build(
            "![a](a.png)\n![b](b.png)", theme: .standard(), newlineStyle: .lineBreak
        )
        guard case .images(let images) = blocks.first?.content else {
            Issue.record("画像のブロックが取れていない")
            return
        }
        #expect(images.count == 2)
    }
}

/// 改行1つで段落を分ける（D-74）。日本語の文章の書き方に合わせたもの。
@Suite("改行で段落を分ける")
struct NewlineParagraphTests {

    func build(_ source: String) -> [PreviewBlock] {
        PreviewBuilder.build(source, theme: .standard(), newlineStyle: .paragraph)
    }

    func paragraphs(_ blocks: [PreviewBlock]) -> [String] {
        blocks.compactMap { block in
            guard case .paragraph(let text) = block.content else { return nil }
            return String(text.characters)
        }
    }

    @Test("改行1つで、別々の段落になる")
    func newlineSplitsParagraphs() {
        let blocks = build("　あいう。\n　えお。")
        #expect(paragraphs(blocks) == ["　あいう。", "　えお。"])
    }

    @Test("行末の半角スペース2つの改行も、段落を分ける")
    func hardBreakAlsoSplits() {
        #expect(paragraphs(build("あ  \nい\nう")) == ["あ", "い", "う"])
    }

    @Test("分けた段落は、それぞれ自分の行を持つ（スクロールの追従に使う）")
    func eachParagraphKeepsItsLine() {
        let blocks = build("見出しの前\n\nあ\nい\nう")
        #expect(blocks.map(\.sourceLine) == [1, 3, 4, 5])
        #expect(blocks.blockID(containing: 4) == blocks[2].id)
        #expect(Set(blocks.map(\.id)).count == blocks.count)
    }

    @Test("リストと引用の中は、段落に分けず折り返す")
    func listAndQuoteOnlyBreakLines() {
        let list = build("- あ\n  い")
        guard case .list(let items) = list.first?.content,
              case .paragraph(let text) = items.items.first?.blocks.first?.content
        else {
            Issue.record("リストが取れていない")
            return
        }
        #expect(items.items.first?.blocks.count == 1)
        #expect(String(text.characters) == "あ\nい")

        let quote = build("> あ\n> い")
        guard case .quote(let blocks) = quote.first?.content else {
            Issue.record("引用が取れていない")
            return
        }
        #expect(paragraphs(blocks) == ["あ\nい"])
    }

    @Test("画像だけの段落は、分けずに1つの絵のまとまりのまま")
    func imagesOnlyParagraphStaysTogether() {
        let blocks = build("![a](a.png)\n![b](b.png)")
        #expect(blocks.count == 1)
        guard case .images(let images) = blocks.first?.content else {
            Issue.record("画像のブロックが取れていない")
            return
        }
        #expect(images.count == 2)
    }

    @Test("画像だけの行は、分けたあと絵になる")
    func imageLineBecomesPicture() {
        let blocks = build("![a](a.png){.right}\n　本文です。")
        guard blocks.count == 2, case .images(let images) = blocks[0].content else {
            Issue.record("画像の行が絵になっていない")
            return
        }
        #expect(images.first?.source == "a.png")
        #expect(paragraphs(blocks) == ["　本文です。"])
    }

    @Test("見出しや空行の段落は、今までどおり")
    func otherBlocksAreUnchanged() {
        let blocks = build("# 題\n\nあ\n\nい")
        #expect(blocks.count == 3)
        #expect(paragraphs(blocks) == ["あ", "い"])
    }
}
