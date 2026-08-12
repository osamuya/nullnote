import Foundation
import Testing
@testable import NullnoteUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("ハイライタ")
struct MarkdownHighlighterTests {

    let theme = MarkdownTheme.standard()

    /// ソースをハイライトし、指定した部分文字列の位置にある属性を返す。
    func attributes(of substring: String, in source: String) -> [NSAttributedString.Key: Any] {
        let storage = NSMutableAttributedString(string: source)
        var highlighter = MarkdownHighlighter(theme: theme); highlighter.apply(to: storage, text: source)

        let range = (source as NSString).range(of: substring)
        #expect(range.location != NSNotFound, "\"\(substring)\" が見つからない")
        return storage.attributes(at: range.location, effectiveRange: nil)
    }

    func font(of substring: String, in source: String) -> PlatformFont? {
        attributes(of: substring, in: source)[.font] as? PlatformFont
    }

    func color(of substring: String, in source: String) -> PlatformColor? {
        attributes(of: substring, in: source)[.foregroundColor] as? PlatformColor
    }

    // MARK: - 色

    @Test("記法文字は薄い色になる")
    func markersAreDimmed() {
        #expect(color(of: "#", in: "# Title") === theme.marker)
        #expect(color(of: "|", in: "| a |\n| - |") === theme.marker)
    }

    @Test("見出しの本文は見出し色になる")
    func headingUsesHeadingColor() {
        #expect(color(of: "Title", in: "# Title") === theme.heading)
    }

    @Test("リンクとオートリンクはリンク色になる")
    func linksUseLinkColor() {
        #expect(color(of: "Apple", in: "[Apple](https://apple.com)") === theme.link)
        #expect(color(of: "https://example.com", in: "見て https://example.com") === theme.link)
    }

    @Test("引用は引用色になる")
    func quoteUsesQuoteColor() {
        #expect(color(of: "quoted", in: "> quoted") === theme.quote)
    }

    @Test("チェックボックスはアクセント色になる")
    func taskMarkerUsesAccent() {
        #expect(color(of: "[x]", in: "- [x] done") === theme.accent)
    }

    // MARK: - フォント

    @Test("見出しは本文より大きく、太字になる")
    func headingIsLargerAndBold() {
        let heading = font(of: "Title", in: "# Title")
        #expect(heading?.pointSize == theme.headingFontSize(level: 1))
        #expect(heading?.isBold == true)
    }

    @Test("見出しのレベルが深いほど小さくなる")
    func headingSizeShrinksWithLevel() {
        let h1 = font(of: "A", in: "# A")?.pointSize ?? 0
        let h3 = font(of: "A", in: "### A")?.pointSize ?? 0
        let h6 = font(of: "A", in: "###### A")?.pointSize ?? 0
        #expect(h1 > h3)
        #expect(h3 > h6)
        #expect(h6 == theme.fontSize)
    }

    @Test("コードは等幅になる")
    func codeIsMonospaced() {
        #expect(font(of: "let x", in: "`let x`")?.isMonospaced == true)
        #expect(font(of: "let x", in: "```\nlet x\n```")?.isMonospaced == true)
    }

    @Test("強調は斜体、強い強調は太字になる")
    func emphasisTraits() {
        #expect(font(of: "italic", in: "*italic*")?.isItalic == true)
        #expect(font(of: "bold", in: "**bold**")?.isBold == true)
    }

    @Test("入れ子の強調は特性が合成される")
    func nestedEmphasisCombinesTraits() {
        let inner = font(of: "italic", in: "**bold *italic***")
        #expect(inner?.isBold == true)
        #expect(inner?.isItalic == true)
    }

    @Test("*** は太字かつ斜体になる")
    func tripleAsteriskCombinesTraits() {
        let both = font(of: "both", in: "***both***")
        #expect(both?.isBold == true)
        #expect(both?.isItalic == true)
    }

    @Test("表のヘッダセルは太字になる")
    func tableHeaderIsBold() {
        #expect(font(of: "name", in: "| name |\n| --- |\n| a |")?.isBold == true)
    }

    // MARK: - その他の属性

    @Test("取り消し線が引かれる")
    func strikethroughIsApplied() {
        let attributes = attributes(of: "gone", in: "~~gone~~")
        #expect(attributes[.strikethroughStyle] as? Int == NSUnderlineStyle.single.rawValue)
    }

    @Test("コードには背景色が付く")
    func codeHasBackground() {
        let attributes = attributes(of: "x", in: "`x`")
        #expect(attributes[.backgroundColor] as? PlatformColor === theme.codeBackground)
    }

    // MARK: - 位置合わせ

    @Test("絵文字や日本語があっても属性が正しい位置に載る")
    func offsetsSurviveNonASCII() {
        let source = "# 🇯🇵 日本語の見出し\n本文に **強調** がある"
        #expect(color(of: "日本語の見出し", in: source) === theme.heading)
        #expect(font(of: "強調", in: source)?.isBold == true)
        // 見出しの後ろの本文が見出し色に染まっていないこと。
        #expect(color(of: "がある", in: source) === theme.text)
    }

    @Test("空文字列でも落ちない")
    func emptyDocument() {
        let storage = NSMutableAttributedString(string: "")
        var highlighter = MarkdownHighlighter(theme: theme); highlighter.apply(to: storage, text: "")
        #expect(storage.length == 0)
    }

    @Test("属性は文書全体を覆い、隙間ができない")
    func attributesCoverWholeDocument() {
        let source = "# Title\n\n- [ ] task\n\n| a | b |\n| - | - |\n| 1 | 2 |\n"
        let storage = NSMutableAttributedString(string: source)
        var highlighter = MarkdownHighlighter(theme: theme); highlighter.apply(to: storage, text: source)

        var covered = 0
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value != nil { covered += range.length }
        }
        #expect(covered == storage.length)
    }
}

// MARK: - フォント特性の判定

extension PlatformFont {
    var isBold: Bool {
        #if canImport(AppKit)
        fontDescriptor.symbolicTraits.contains(.bold)
        #else
        fontDescriptor.symbolicTraits.contains(.traitBold)
        #endif
    }

    var isItalic: Bool {
        #if canImport(AppKit)
        fontDescriptor.symbolicTraits.contains(.italic)
        #else
        fontDescriptor.symbolicTraits.contains(.traitItalic)
        #endif
    }

    var isMonospaced: Bool {
        #if canImport(AppKit)
        fontDescriptor.symbolicTraits.contains(.monoSpace)
        #else
        fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
        #endif
    }
}
