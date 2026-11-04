import Foundation
import Testing
@testable import NullnoteUI

@Suite("プレビューのリンクの行き先（#013）")
struct PreviewLinkTests {

    let document = URL(fileURLWithPath: "/Users/someone/文書/株取引/_目次.md")

    /// `PreviewModel` と同じく、書かれた文字から URL を作って解く。
    func resolve(_ destination: String, document: URL? = nil) -> PreviewLinkTarget? {
        guard let url = URL(string: destination) else { return nil }
        return PreviewLinkResolver.resolve(url, relativeTo: document ?? self.document)
    }

    func local(_ path: String) -> PreviewLinkTarget {
        .local(URL(fileURLWithPath: path))
    }

    @Test("相対パスは文書のフォルダを基準にする")
    func relative() {
        #expect(resolve("./株のお話_投資について学んでおきたいこと")
            == local("/Users/someone/文書/株取引/株のお話_投資について学んでおきたいこと"))
        #expect(resolve("メモ.md") == local("/Users/someone/文書/株取引/メモ.md"))
        #expect(resolve("../共有/メモ.md") == local("/Users/someone/文書/共有/メモ.md"))
    }

    @Test("符号化された名前を戻す")
    func percentEncoded() {
        #expect(resolve("./%E6%A0%AA%20%E5%8F%96%E5%BC%95.md") == local("/Users/someone/文書/株取引/株 取引.md"))
    }

    @Test("見出しへの #… は外してファイルを指す")
    func fragment() {
        #expect(resolve("./メモ.md#はじめに") == local("/Users/someone/文書/株取引/メモ.md"))
    }

    @Test("絶対パス・~/・file:")
    func absolute() {
        #expect(resolve("/tmp/a.md") == local("/tmp/a.md"))
        #expect(resolve("file:///tmp/a.md") == local("/tmp/a.md"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(resolve("~/a.md") == local("\(home)/a.md"))
    }

    @Test("https: や mailto: は OS に任せる")
    func external() {
        #expect(resolve("https://sabanote.com/") == .external(URL(string: "https://sabanote.com/")!))
        #expect(resolve("mailto:a@example.com") == .external(URL(string: "mailto:a@example.com")!))
    }

    @Test("文書内の見出しだけ・未保存の相対パスは決めない")
    func undecided() {
        #expect(resolve("#はじめに") == nil)
        let url = URL(string: "./メモ.md")!
        #expect(PreviewLinkResolver.resolve(url, relativeTo: nil) == nil)
    }

    @Test("拡張子が無ければ .md・.markdown も探す")
    func candidates() {
        let bare = URL(fileURLWithPath: "/a/株のお話")
        #expect(PreviewLinkResolver.candidates(for: bare).map(\.path)
            == ["/a/株のお話", "/a/株のお話.md", "/a/株のお話.markdown"])
        let withExtension = URL(fileURLWithPath: "/a/図.png")
        #expect(PreviewLinkResolver.candidates(for: withExtension) == [withExtension])
    }

    @Test("Nullnote で開くのは .md と .markdown")
    func markdown() {
        #expect(PreviewLinkResolver.isMarkdown(URL(fileURLWithPath: "/a/b.md")))
        #expect(PreviewLinkResolver.isMarkdown(URL(fileURLWithPath: "/a/b.MARKDOWN")))
        #expect(!PreviewLinkResolver.isMarkdown(URL(fileURLWithPath: "/a/b.pdf")))
    }
}
