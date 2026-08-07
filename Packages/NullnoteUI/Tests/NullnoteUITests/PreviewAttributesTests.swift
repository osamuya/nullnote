#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

/// `AttributedString`（意味づけ）→ AppKit の属性 への変換。
///
/// プレビューの本文は `NSTextView` で描くため、
/// `inlinePresentationIntent` を AppKit の属性へ落とし直している。
/// SwiftUI 用に焼き込んだフォントや色ではなく、**意味づけ**を読んでいることを確かめる。
@Suite("プレビューの属性変換")
@MainActor
struct PreviewAttributesTests {

    let theme = MarkdownTheme.standard()

    func convert(_ source: String) -> NSAttributedString {
        guard case .paragraph(let text) = PreviewBuilder.build(source, theme: theme).first?.content else {
            return NSAttributedString()
        }
        return PreviewAttributes.make(
            from: text, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text
        )
    }

    /// 指定した部分文字列の位置にある属性を取り出す。
    func attributes(of substring: String, in source: String) -> [NSAttributedString.Key: Any] {
        let attributed = convert(source)
        let range = (attributed.string as NSString).range(of: substring)
        #expect(range.location != NSNotFound, "\"\(substring)\" が見つからない")
        guard range.location != NSNotFound else { return [:] }
        return attributed.attributes(at: range.location, effectiveRange: nil)
    }

    // MARK: - 装飾

    @Test("強調は太字になる")
    func strong() {
        let font = attributes(of: "bold", in: "**bold** ふつう")[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test("斜体は italic になる")
    func emphasis() {
        let font = attributes(of: "italic", in: "*italic* ふつう")[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
    }

    @Test("取り消し線が引かれる")
    func strikethrough() {
        let attributes = attributes(of: "gone", in: "~~gone~~ ふつう")
        #expect(attributes[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("インラインコードは等幅・コード色・背景つきになる")
    func inlineCode() {
        let attributes = attributes(of: "code", in: "`code` ふつう")
        let font = attributes[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        #expect(attributes[.foregroundColor] as? NSColor === theme.code)
        #expect(attributes[.backgroundColor] as? NSColor === theme.codeBackground)
    }

    @Test("装飾の無い文字は基本のフォントと色のまま")
    func plainText() {
        let attributes = attributes(of: "ふつう", in: "**bold** ふつう")
        #expect(attributes[.foregroundColor] as? NSColor === theme.text)
        #expect((attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == false)
    }

    // MARK: - リンク

    @Test("リンクに URL が載る")
    func link() {
        let attributes = attributes(of: "Apple", in: "[Apple](https://apple.com) ふつう")
        #expect(attributes[.link] as? URL == URL(string: "https://apple.com"))
    }

    @Test("裸の URL にも URL が載る")
    func bareURL() {
        let attributes = attributes(of: "https://example.com", in: "見て https://example.com")
        #expect(attributes[.link] != nil)
    }

    @Test("リンクでない文字には URL が載らない")
    func notALink() {
        #expect(attributes(of: "ふつう", in: "[Apple](https://apple.com) ふつう")[.link] == nil)
    }

    // MARK: - 基本の指定

    @Test("見出し用のフォントと色を渡すと反映される")
    func customBaseFontAndColor() {
        guard case .heading(_, let text) = PreviewBuilder.build("# 見出し", theme: theme).first?.content else {
            Issue.record("見出しが取れていない")
            return
        }
        let big = PlatformFont.editorBody(size: 30).addingTraits(bold: true)
        let attributed = PreviewAttributes.make(
            from: text, theme: theme, baseFont: big, baseColor: theme.heading
        )
        let attributes = attributed.attributes(at: 0, effectiveRange: nil)
        #expect((attributes[.font] as? NSFont)?.pointSize == 30)
        #expect(attributes[.foregroundColor] as? NSColor === theme.heading)
    }

    @Test("空でも落ちない")
    func empty() {
        #expect(PreviewAttributes.make(
            from: AttributedString(), theme: theme, baseFont: theme.bodyFont, baseColor: theme.text
        ).length == 0)
    }
}
#endif
