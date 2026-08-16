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

    @Test("文字が混ざっていたら段落のまま")
    func imageWithText() {
        // 文中の画像を絵にすると、行の流れが切れて読みにくくなる。
        #expect(images("これは ![マタギ](image1.jpg) の写真です。\n") == nil)
        #expect(images("![マタギ](image1.jpg) 補足\n") == nil)
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
