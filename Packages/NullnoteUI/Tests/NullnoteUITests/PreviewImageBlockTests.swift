import Testing
@testable import NullnoteUI

/// 画像を「絵として置く」か「代替テキストのままにする」かの切り分け。
@Suite("画像のブロック化")
struct PreviewImageBlockTests {

    func blocks(_ source: String) -> [PreviewBlock] {
        PreviewBuilder.build(source, theme: .standard())
    }

    func images(_ source: String) -> [PreviewImageRef]? {
        guard case .images(let images) = blocks(source).first?.content else { return nil }
        return images
    }

    @Test("画像だけの段落は絵になる")
    func imageOnlyParagraph() {
        let found = images("![マタギ](image1.jpg)\n")
        #expect(found?.count == 1)
        #expect(found?.first?.source == "image1.jpg")
        #expect(found?.first?.alt == "マタギ")
    }

    @Test("空行を挟まずに並べた画像も、まとめて絵になる")
    func consecutiveImages() {
        // Markdown では続けて書いた行は1つの段落になる。
        // 「1枚だけ」を条件にしていたときは、ここが代替テキストに落ちていた。
        let found = images("![一枚目](a.jpg)\n![二枚目](b.jpg)\n")
        #expect(found?.count == 2)
        #expect(found?.map(\.alt) == ["一枚目", "二枚目"])
    }

    @Test("空行で分けた画像は、別々の絵になる")
    func separatedImages() {
        let all = blocks("![一枚目](a.jpg)\n\n![二枚目](b.jpg)\n")
        #expect(all.count == 2)
        for block in all {
            guard case .images(let images) = block.content else {
                Issue.record("絵になっていない"); continue
            }
            #expect(images.count == 1)
        }
    }

    /// ブロックを「絵」か「文字」の並びにして返す。比べやすくするため。
    func shape(_ source: String) -> [String] {
        blocks(source).map { block in
            switch block.content {
            case .images(let images): "絵:" + images.map(\.source).joined(separator: ",")
            case .paragraph(let text): "文:" + String(text.characters)
            default: "その他"
            }
        }
    }

    @Test("画像の行の次に空行が無くても、画像は絵になる（#019）")
    func imageLineFollowedByText() {
        #expect(shape("![hoge](./dummy.png)\n続きの文です。\n") == ["絵:./dummy.png", "文:続きの文です。"])
        #expect(shape("前の文です。\n![hoge](./dummy.png)\n") == ["文:前の文です。", "絵:./dummy.png"])
        #expect(shape("前の文。\n![a](a.png)\n後の文。\n") == ["文:前の文。", "絵:a.png", "文:後の文。"])
    }

    @Test("文字と同じ行の画像も絵になる。文字は前後の段落に分かれる（#019）")
    func imageWithText() {
        #expect(shape("これは ![マタギ](image1.jpg) の写真です。\n")
            == ["文:これは", "絵:image1.jpg", "文:の写真です。"])
        #expect(shape("![マタギ](image1.jpg) 補足\n") == ["絵:image1.jpg", "文:補足"])
    }

    @Test("文字の行どうしは、これまでどおり1つの段落につながる")
    func textLinesStayJoined() {
        #expect(shape("一行目\n二行目\n![a](a.png)\n") == ["文:一行目 二行目", "絵:a.png"])
    }

    @Test("文字が混ざっていても、置き方の指定は直前の画像に効く")
    func layoutMarkerWithText() {
        let all = blocks("![a](a.png){.center} 補足\n本文\n")
        guard all.count == 2, case .images(let images) = all[0].content else {
            Issue.record("絵になっていない"); return
        }
        #expect(images.first?.layout == .center)
        #expect(shape("![a](a.png){.center} 補足\n本文\n") == ["絵:a.png", "文:補足 本文"])
    }

    @Test("文字を挟まずに続けた画像は、文字が混ざる段落でも1つのまとまり")
    func consecutiveImagesWithText() {
        #expect(shape("![a](a.png)\n![b](b.png)\n本文\n") == ["絵:a.png,b.png", "文:本文"])
    }

    @Test("リンクで包んだ画像は代替テキストのまま")
    func linkedImageStaysText() {
        #expect(shape("[![a](a.png)](https://example.com)\n") == ["文:🖼 a"])
    }

    @Test("分けたブロックは、それぞれ書かれた行を指す")
    func sourceLinesAfterSplit() {
        let all = blocks("前の文。\n![a](a.png)\n後の文。\n")
        #expect(all.map(\.sourceLine) == [1, 2, 3])
    }

    @Test("引用とリストの中でも、画像は絵になる")
    func imageInsideQuoteAndList() {
        guard case .quote(let quoted) = blocks("> ![a](a.png)\n> 補足\n").first?.content else {
            Issue.record("引用になっていない"); return
        }
        guard case .images = quoted.first?.content else { Issue.record("引用の中が絵になっていない"); return }
        guard case .list(let list) = blocks("- 項目 ![a](a.png)\n").first?.content,
              list.items.first?.blocks.count == 2,
              case .images = list.items.first?.blocks.last?.content
        else { Issue.record("リストの中が絵になっていない"); return }
    }

    @Test("画像の id は重ならない")
    func uniqueIdentifiers() {
        let found = images("![a](a.jpg)\n![b](b.jpg)\n![c](c.jpg)\n")
        let ids = found?.map(\.id) ?? []
        #expect(ids.count == 3)
        #expect(Set(ids).count == ids.count)
    }

    @Test("代替テキストが無くても絵になる")
    func imageWithoutAlt() {
        let found = images("![](image1.jpg)\n")
        #expect(found?.count == 1)
        #expect(found?.first?.alt == "")
    }
}
