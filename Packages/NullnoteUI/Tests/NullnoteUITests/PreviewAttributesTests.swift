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

    /// 表の列の揃え。
    ///
    /// 揃えは段落スタイルに入れる。テキストビューは提案された幅いっぱいに
    /// 広がるため、外側の `frame(alignment:)` では効かない。
    @Test(
        "指定した揃えが段落スタイルに載る",
        arguments: [NSTextAlignment.natural, .center, .right]
    )
    func alignmentIsCarried(alignment: NSTextAlignment) throws {
        guard case .paragraph(let text) = PreviewBuilder.build("本文", theme: theme).first?.content else {
            Issue.record("段落が作れない"); return
        }
        let attributed = PreviewAttributes.make(
            from: text, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text,
            alignment: alignment
        )
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        let paragraph = try #require(style as? NSParagraphStyle)
        #expect(paragraph.alignment == alignment)
    }

    /// 回帰テスト（決定記録 D-18）。
    ///
    /// 測る側に揃えを入れると、グリフがコンテナ幅いっぱいに配置されて
    /// 測った幅が実際の文字幅より広くなる。既定は必ず `.natural`。
    @Test("既定では揃えを入れない（測定用に使うため）")
    func defaultAlignmentIsNatural() throws {
        guard case .paragraph(let text) = PreviewBuilder.build("本文", theme: theme).first?.content else {
            Issue.record("段落が作れない"); return
        }
        let attributed = PreviewAttributes.make(
            from: text, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text
        )
        let style = attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
        let paragraph = try #require(style as? NSParagraphStyle)
        #expect(paragraph.alignment == .natural)
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

    /// 細い線を1本引くだけだと、ぱっと見でふつうの文字と区別が付かない。
    /// 線を太くしたうえで、文字自体も沈ませる。
    @Test("取り消し線は太く、文字も沈む")
    func strikethrough() {
        let struck = attributes(of: "gone", in: "~~gone~~ ふつう")
        #expect(struck[.strikethroughStyle] as? Int == NSUnderlineStyle.thick.rawValue)
        #expect(struck[.foregroundColor] as? NSColor == theme.struckText)
        #expect(struck[.strikethroughColor] as? NSColor == theme.struckText)

        // 同じ段落のふつうの文字は、本文の色のまま。
        let plain = attributes(of: "ふつう", in: "~~gone~~ ふつう")
        #expect(plain[.strikethroughStyle] == nil)
        #expect(plain[.foregroundColor] as? NSColor == theme.text)
    }

    @Test("取り消した文字は本文より沈んでいる")
    func struckTextIsMuted() throws {
        let target = try #require(NSAppearance(named: .darkAqua))
        var struckBrightness = 0.0
        var textBrightness = 0.0
        target.performAsCurrentDrawingAppearance {
            struckBrightness = Double(theme.struckText.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0)
            textBrightness = Double(theme.text.usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0)
        }
        // ダークでは本文が明るいので、沈む＝暗くなる。
        #expect(struckBrightness < textBrightness, "取り消した文字が本文と同じ強さで出ている")
    }

    @Test("インラインコードは等幅・札の色・背景つきになる")
    func inlineCode() {
        let attributes = attributes(of: "code", in: "`code` ふつう")
        let font = attributes[.font] as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        // 編集画面とは色を分けている。あちらは記法文字が見えているぶん、
        // 地の色をうっすら変えるだけでよい（`theme.code` / `theme.codeBackground`）。
        #expect(attributes[.foregroundColor] as? NSColor === theme.inlineCodeText)
        #expect(attributes[.backgroundColor] as? NSColor === theme.inlineCodeBackground)
    }

    @Test("札の左右に余白と隙間ができる")
    func inlineCodeSpacing() throws {
        let attributed = convert("あ `code` い")
        let string = attributed.string as NSString
        let code = string.range(of: "code")
        let padding = theme.inlineCodePadding

        // 直前の字との隙間。
        let spacer = code.location - 1
        let gapBefore = attributed.attribute(.kern, at: spacer - 1, effectiveRange: nil) as? CGFloat
        #expect(gapBefore == padding)
        // 札の中の左の余白。幅ゼロの文字に持たせてある。
        #expect(string.substring(with: NSRange(location: spacer, length: 1)) == PreviewAttributes.leadingSpacer)
        #expect(attributed.attribute(.kern, at: spacer, effectiveRange: nil) as? CGFloat == padding)
        // 札の中の右の余白と、次の字との隙間。
        #expect(attributed.attribute(.kern, at: NSMaxRange(code) - 1, effectiveRange: nil) as? CGFloat == padding * 2)
        // 中ほどの文字は広げない（字間が開いて読みにくくなる）。
        #expect(attributed.attribute(.kern, at: code.location, effectiveRange: nil) == nil)
    }

    /// 回帰テスト。
    ///
    /// 余白を「札の矩形を左へ広げる」で作っていたころ、行やマスの先頭では
    /// 左に広げる余地が無く、余白が 0 に潰れていた。
    @Test("行頭の札でも左の余白が潰れない")
    func inlineCodeAtStartKeepsPadding() throws {
        let attributed = convert("`code` のあと")
        // 先頭は幅ゼロの文字。そこに左の余白が入っている。
        #expect((attributed.string as NSString).substring(to: 1) == PreviewAttributes.leadingSpacer)
        #expect(attributed.attribute(.kern, at: 0, effectiveRange: nil) as? CGFloat == theme.inlineCodePadding)
    }

    @Test("余白に使う文字は改行してよい位置にしない")
    func leadingSpacerDoesNotBreakLines() {
        // U+200B（ZERO WIDTH SPACE）だと、札の頭だけが行末に取り残されることがある。
        #expect(PreviewAttributes.leadingSpacer == "\u{2060}")
    }

    @Test("測る文字列にも同じ隙間が入る")
    func measuringIncludesSpacing() throws {
        // 表示用にだけ隙間を入れると、札のぶんだけ幅が足りず折り返しがずれる。
        guard case .paragraph(let text) = PreviewBuilder.build("あ `code` い", theme: theme).first?.content else {
            Issue.record("段落が作れない"); return
        }
        let measuring = PreviewAttributes.make(
            from: text, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text
        )
        let display = PreviewAttributes.make(
            from: text, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text, alignment: .center
        )
        #expect(measuring.size().width == display.size().width)
        #expect(measuring.size().width > 0)
    }

    @Test("札の色は編集画面のコード色と別物")
    func inlineCodeDiffersFromEditor() throws {
        // 同じ値にすると、片方を直したときにもう片方が黙って変わる。
        for appearance in [MarkdownAppearance.light, .dark] {
            let theme = MarkdownTheme.standard(appearance: appearance)
            let target = try #require(NSAppearance(named: appearance == .light ? .aqua : .darkAqua))
            target.performAsCurrentDrawingAppearance {
                #expect(theme.inlineCodeText.usingColorSpace(.sRGB) != theme.code.usingColorSpace(.sRGB))
                #expect(theme.inlineCodeBackground.usingColorSpace(.sRGB) != theme.codeBackground.usingColorSpace(.sRGB))
            }
        }
    }

    @Test("札の中の文字は地に対して読める", arguments: [MarkdownAppearance.light, .dark])
    func inlineCodeIsLegible(appearance: MarkdownAppearance) throws {
        let theme = MarkdownTheme.standard(appearance: appearance)
        let target = try #require(NSAppearance(named: appearance == .light ? .aqua : .darkAqua))

        var onChip = 0.0
        var chipOnPage = 0.0
        target.performAsCurrentDrawingAppearance {
            onChip = Self.contrast(theme.inlineCodeText, theme.inlineCodeBackground)
            chipOnPage = Self.contrast(theme.inlineCodeBackground, theme.background)
        }
        #expect(onChip >= 4.5, "札の中の文字が読めない: \(onChip)")
        // ライトは地の差が小さいぶん、枠線で形を示している（下のテスト）。
        #expect(chipOnPage >= 1.05, "札が背景に溶けている: \(chipOnPage)")
    }

    @Test("札には必ず枠線がある", arguments: [MarkdownAppearance.light, .dark])
    func borderIsAlwaysVisible(appearance: MarkdownAppearance) throws {
        // ライトは札の地とページ背景の差が 1.06 しかなく、枠線が無いと札に見えない。
        // ダークは地でも浮くが、線を入れると縁が締まる。
        let theme = MarkdownTheme.standard(appearance: appearance)
        let target = try #require(NSAppearance(named: appearance == .light ? .aqua : .darkAqua))
        target.performAsCurrentDrawingAppearance {
            let border = theme.inlineCodeBorder.usingColorSpace(.sRGB)
            #expect(border != theme.inlineCodeBackground.usingColorSpace(.sRGB))
            #expect((border?.alphaComponent ?? 0) > 0)
        }
    }

    @Test("角は丸めすぎない")
    func cornerRadiusStaysSubtle() {
        // カプセル状にすると、文中でボタンと見分けが付かなくなる。
        let theme = MarkdownTheme.standard(fontSize: 14)
        #expect(theme.inlineCodeCornerRadius < theme.inlineCodeHeight / 2)
        #expect(theme.inlineCodeCornerRadius > 0)
    }

    /// WCAG のコントラスト比。
    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            guard let c = color.usingColorSpace(.sRGB) else { return 0 }
            func channel(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c.redComponent)
                + 0.7152 * channel(c.greenComponent)
                + 0.0722 * channel(c.blueComponent)
        }
        let high = max(luminance(a), luminance(b))
        let low = min(luminance(a), luminance(b))
        return (high + 0.05) / (low + 0.05)
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
