import Foundation
import Testing
@testable import NullnoteUI

/// 普通の改行をどう見せるか（D-33）。
///
/// 既定は CommonMark どおり、ひと続きの行として畳む。
/// 設定を入れた人にだけ、書いたとおりの位置で折る。**本文は書き換えない。**
@Suite("普通の改行の見せ方")
struct SoftBreakTests {

    func paragraph(_ source: String, breaksOnNewline: Bool) -> String? {
        let blocks = PreviewBuilder.build(
            source, theme: .standard(), breaksOnNewline: breaksOnNewline
        )
        guard case .paragraph(let text) = blocks.first?.content else { return nil }
        return String(text.characters)
    }

    @Test("既定では、普通の改行はスペースに畳まれる")
    func softBreakFoldsByDefault() {
        #expect(paragraph("あ\nい", breaksOnNewline: false) == "あ い")
    }

    @Test("設定を入れると、普通の改行がそのまま改行になる")
    func softBreakBecomesLineBreak() {
        #expect(paragraph("あ\nい", breaksOnNewline: true) == "あ\nい")
    }

    @Test("半角スペース2つの改行は、どちらの設定でも改行のまま")
    func hardBreakIsAlwaysBreak() {
        #expect(paragraph("あ  \nい", breaksOnNewline: false) == "あ\nい")
        #expect(paragraph("あ  \nい", breaksOnNewline: true) == "あ\nい")
    }

    @Test("空行で区切った段落は、設定に関わらず別のブロックのまま")
    func blankLineStillSplitsParagraphs() {
        for breaks in [false, true] {
            let blocks = PreviewBuilder.build(
                "あ\n\nい", theme: .standard(), breaksOnNewline: breaks
            )
            #expect(blocks.count == 2)
        }
    }

    @Test("リストや引用の中でも同じ扱いになる")
    func insideListAndQuote() {
        let list = PreviewBuilder.build(
            "- あ\n  い", theme: .standard(), breaksOnNewline: true
        )
        guard case .list(let items) = list.first?.content,
              case .paragraph(let text) = items.items.first?.blocks.first?.content
        else {
            Issue.record("リストが取れていない")
            return
        }
        #expect(String(text.characters) == "あ\nい")

        let quote = PreviewBuilder.build(
            "> あ\n> い", theme: .standard(), breaksOnNewline: true
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
            "![a](a.png)\n![b](b.png)", theme: .standard(), breaksOnNewline: true
        )
        guard case .images(let images) = blocks.first?.content else {
            Issue.record("画像のブロックが取れていない")
            return
        }
        #expect(images.count == 2)
    }
}
