import Testing
@testable import NullnoteUI

/// `{.center}` のような置き方の指定。
///
/// **Markdown の標準ではない。** 記法として読み損ねると、
/// `{.center}` の文字が本文に出る。
@Suite("画像の置き方の指定")
struct ImageLayoutTests {

    func images(_ source: String) -> [PreviewImageRef] {
        guard case .images(let images) = PreviewBuilder.build(source, theme: .standard()).first?.content
        else { return [] }
        return images
    }

    @Test("指定が無ければ、そのまま置く")
    func noMarker() {
        #expect(images("![絵](a.jpg)\n").map(\.layout) == [.normal])
    }

    @Test("中央寄せを読む")
    func center() {
        #expect(images("![絵](a.jpg){.center}\n").map(\.layout) == [.center])
    }

    @Test("サムネイルを読む")
    func thumbnail() {
        #expect(images("![絵](a.jpg){.thumbnail}\n").map(\.layout) == [.thumbnail])
    }

    @Test("並べたサムネイルを、それぞれ読む")
    func severalThumbnails() {
        let found = images("![1](a.jpg){.thumbnail}\n![2](b.jpg){.thumbnail}\n![3](c.jpg){.thumbnail}\n")
        #expect(found.count == 3)
        #expect(found.allSatisfy { $0.layout == .thumbnail })
    }

    @Test("指定は直前の画像にだけ効く")
    func markerAppliesToPrecedingImage() {
        let found = images("![1](a.jpg){.center}\n![2](b.jpg)\n")
        #expect(found.map(\.layout) == [.center, .normal])
    }

    @Test("知らない名前は指定なし扱い")
    func unknownMarker() {
        // 増やしたときに古い文書が壊れないよう、黙って無視する。
        #expect(images("![絵](a.jpg){.wobble}\n").map(\.layout) == [.normal])
    }

    @Test("指定のあとに文字が続いても、指定は効く。文字は後ろの段落になる（D-76）")
    func textAfterMarker() {
        let all = PreviewBuilder.build("![絵](a.jpg){.center} という写真\n", theme: .standard())
        #expect(images("![絵](a.jpg){.center} という写真\n").map(\.layout) == [.center])
        guard all.count == 2, case .paragraph(let text) = all[1].content else {
            Issue.record("後ろの文字が段落になっていない"); return
        }
        #expect(String(text.characters) == "という写真")
    }

    @Test("画像が無いところの {.center} は、ただの文字")
    func markerWithoutImage() {
        #expect(images("{.center} だけの行\n").isEmpty)
    }

    @Test("指定と画像のあいだに空白があってもよい")
    func whitespaceBeforeMarker() {
        #expect(images("![絵](a.jpg) {.center}\n").map(\.layout) == [.center])
    }
}

extension ImageLayoutTests {

    /// 回帰テスト。
    ///
    /// `{. center}` と書かれていて効かず、「なぜ効かないのか分からない」状態になった。
    /// 空白ひとつで落ちるのは、書く側に厳しすぎる。
    @Test(
        "ドットや名前の周りに空白があっても読む",
        arguments: ["{.center}", "{. center}", "{ .center}", "{ . center }", "{.CENTER}"]
    )
    func lenientAboutWhitespace(marker: String) {
        #expect(images("![絵](a.jpg)\(marker)\n").map(\.layout) == [.center])
    }

    @Test("中かっこでもドットが無ければ、ただの文字")
    func bracesWithoutDot() {
        // `{注釈}` のような書き方を、置き方の指定と取り違えない。
        // 画像は絵になり、`{center}` は後ろの段落の文字として残る（D-76）。
        let all = PreviewBuilder.build("![絵](a.jpg){center}\n", theme: .standard())
        #expect(images("![絵](a.jpg){center}\n").map(\.layout) == [.normal])
        guard all.count == 2, case .paragraph(let text) = all[1].content else {
            Issue.record("{center} が文字として残っていない"); return
        }
        #expect(String(text.characters) == "{center}")
    }
}
