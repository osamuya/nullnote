import Foundation
import Testing
@testable import NullnoteUI

@Suite("画像の場所の解釈")
struct ImageSourceTests {

    let document = URL(fileURLWithPath: "/Users/someone/文書/物語/本文.md")

    func resolve(_ source: String) -> ImageSource? {
        ImageSourceResolver.resolve(source, relativeTo: document)
    }

    // MARK: - 手元のファイル

    @Test("文書の隣にある画像")
    func siblingFile() {
        #expect(resolve("image1.jpg") == .local(URL(fileURLWithPath: "/Users/someone/文書/物語/image1.jpg")))
    }

    @Test("文書からの相対パス")
    func relativePath() {
        #expect(resolve("img/写真.png") == .local(URL(fileURLWithPath: "/Users/someone/文書/物語/img/写真.png")))
        #expect(resolve("../共有/写真.png") == .local(URL(fileURLWithPath: "/Users/someone/文書/共有/写真.png")))
        #expect(resolve("./image1.jpg") == .local(URL(fileURLWithPath: "/Users/someone/文書/物語/image1.jpg")))
    }

    @Test("絶対パス")
    func absolutePath() {
        #expect(resolve("/Users/someone/写真/a.jpg") == .local(URL(fileURLWithPath: "/Users/someone/写真/a.jpg")))
    }

    @Test("ホームからのパス")
    func tildePath() {
        let home = NSHomeDirectory()
        #expect(resolve("~/Pictures/a.png") == .local(URL(fileURLWithPath: home + "/Pictures/a.png")))
    }

    @Test("file:// で書かれていても読む")
    func fileURL() {
        #expect(resolve("file:///Users/someone/a.jpg") == .local(URL(fileURLWithPath: "/Users/someone/a.jpg")))
    }

    // MARK: - 網の向こう

    @Test("http と https は読みに行く")
    func remoteImages() {
        #expect(resolve("https://example.com/a.png") == .remote(URL(string: "https://example.com/a.png")!))
        #expect(resolve("http://example.com/a.png") == .remote(URL(string: "http://example.com/a.png")!))
    }

    @Test("扱わない書き方は諦める")
    func unsupportedSchemes() {
        // data: を展開し始めると、文書の中に巨大な塊が入る道が開く。
        #expect(resolve("data:image/png;base64,iVBORw0KGgo=") == nil)
        #expect(resolve("ftp://example.com/a.png") == nil)
    }

    // MARK: - 符号化された名前

    @Test("%20 などは元に戻す")
    func percentEncoded() {
        #expect(resolve("my%20photo.png") == .local(URL(fileURLWithPath: "/Users/someone/文書/物語/my photo.png")))
    }

    @Test("名前に % が入っていても壊さない")
    func literalPercent() {
        // 戻せない並びなら、そのままの名前として扱う。
        #expect(resolve("100%割引.png") == .local(URL(fileURLWithPath: "/Users/someone/文書/物語/100%割引.png")))
    }

    @Test("日本語の名前をそのまま扱える")
    func japaneseFileName() {
        #expect(resolve("猪の写真.jpg") == .local(URL(fileURLWithPath: "/Users/someone/文書/物語/猪の写真.jpg")))
    }

    // MARK: - 決められない場合

    @Test("空なら何も指していない")
    func emptySource() {
        #expect(resolve("") == nil)
        #expect(resolve("   ") == nil)
    }

    @Test("新規の書類では、相対パスの基準が無い")
    func noDocument() {
        // まだ保存していない書類には置き場所が無いので、相対パスは解けない。
        #expect(ImageSourceResolver.resolve("image1.jpg", relativeTo: nil) == nil)
        // 絶対パスと URL は基準が要らない。
        #expect(ImageSourceResolver.resolve("/tmp/a.png", relativeTo: nil) != nil)
        #expect(ImageSourceResolver.resolve("https://example.com/a.png", relativeTo: nil) != nil)
    }
}
