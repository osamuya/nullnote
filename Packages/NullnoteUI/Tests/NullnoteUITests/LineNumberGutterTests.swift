#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

@Suite("行番号")
@MainActor
struct LineNumberGutterTests {

    private func makeTextView(_ text: String, width: CGFloat = 400) -> FocusReportingTextView {
        let textView = FocusReportingTextView(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        textView.string = text
        return textView
    }

    private func gutter(for text: String) -> LineNumberGutter {
        LineNumberGutter(theme: .standard(appearance: .dark), lineIndex: LineIndex(text))
    }

    /// 描いた結果を画素で取り出す。見た目が変わったかの比較に使う。
    private func draw(
        _ gutter: LineNumberGutter,
        on textView: FocusReportingTextView,
        activeLine: Int?
    ) throws -> Data {
        let size = NSSize(width: 200, height: 300)
        let canvas = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        // 帯の外を、帯が使わない色で塗っておく。
        NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        gutter.draw(in: NSRect(origin: .zero, size: size), of: textView, activeLine: activeLine)

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return try #require(canvas.representation(using: .png, properties: [:]))
    }

    @Test("行が増えて桁が上がると帯が広がる")
    func widthGrowsWithDigits() {
        let narrow = gutter(for: "1\n2\n3").width
        let wide = gutter(for: String(repeating: "x\n", count: 1_000)).width
        #expect(wide > narrow, "4桁になっても幅が変わっていない")
    }

    @Test("1〜2行でも帯が潰れない")
    func widthHasMinimum() {
        #expect(gutter(for: "1行だけ").width > 12)
    }

    @Test("本文の余白は帯の幅ぶん広がる")
    func insetIncludesGutter() {
        let g = gutter(for: "1\n2\n3")
        #expect(g.textContainerInsetWidth == g.width + LineNumberGutter.textPadding)
    }

    /// 回帰テスト（決定記録 B-9）。
    ///
    /// 描き直しを求められた範囲をそのまま塗ると、本文まで塗りつぶして消してしまう。
    /// 塗る範囲は必ず帯の幅に閉じ込める。
    @Test("帯の幅より外側を塗らない")
    func drawingStaysInsideGutter() throws {
        let g = gutter(for: "見出し\n本文\n本文")
        let textView = makeTextView("見出し\n本文\n本文")

        let size = NSSize(width: 200, height: 300)
        let canvas = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        // 帯の幅ではなく、ビュー全体を「描き直す範囲」として渡す。
        g.draw(in: NSRect(origin: .zero, size: size), of: textView, activeLine: nil)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let pixel = try #require(canvas.colorAt(x: Int(g.width) + 20, y: 10)?.usingColorSpace(.sRGB))
        #expect(pixel.redComponent > 0.9 && pixel.blueComponent > 0.9 && pixel.greenComponent < 0.1,
                "帯が自分の幅の外まで塗っている（本文が消える）")
    }

    @Test("カーソルのある行だけ見た目が変わる")
    func activeLineIsEmphasized() throws {
        let text = "1行目\n2行目\n3行目"
        let g = gutter(for: text)
        let textView = makeTextView(text)

        let plain = try draw(g, on: textView, activeLine: nil)
        let first = try draw(g, on: textView, activeLine: 1)
        let second = try draw(g, on: textView, activeLine: 2)

        #expect(first != plain, "強調しても見た目が変わっていない")
        #expect(second != first, "強調する行を変えても見た目が変わっていない")
    }

    @Test("焦点の出入りを覚える")
    func focusIsTracked() {
        let textView = makeTextView("本文")
        var notified = 0
        textView.onFocusChange = { notified += 1 }

        #expect(textView.isFocused == false)
        _ = textView.becomeFirstResponder()
        #expect(textView.isFocused)
        #expect(notified == 1)

        // 同じ状態のまま呼ばれても知らせ直さない（無駄な再描画を避ける）。
        _ = textView.becomeFirstResponder()
        #expect(notified == 1)

        _ = textView.resignFirstResponder()
        #expect(textView.isFocused == false)
        #expect(notified == 2)
    }

    @Test("行番号を出していないときは余白を広げない")
    func noGutterKeepsPlainPadding() {
        let textView = makeTextView("本文")
        #expect(textView.lineNumbers == nil)
    }

    /// 回帰テスト（決定記録 B-10）。
    ///
    /// ハイライト色（`selectedTextBackgroundColor`）は選択範囲の「背景」用に
    /// 明度を上げた色で、文字色に使うとライトの背景に埋もれて読めない。
    @Test("強調の色は、ハイライト色そのものより背景と見分けやすい", arguments: [MarkdownAppearance.light, .dark])
    func activeColorIsMoreLegibleThanRawHighlight(appearance: MarkdownAppearance) throws {
        let theme = MarkdownTheme.standard(appearance: appearance)
        let target = try #require(NSAppearance(named: appearance == .light ? .aqua : .darkAqua))

        var chosen = 0.0
        var raw = 0.0
        var saturation = 0.0
        target.performAsCurrentDrawingAppearance {
            chosen = Self.contrast(theme.activeLineNumber, theme.background)
            raw = Self.contrast(.selectedTextBackgroundColor, theme.background)
            saturation = Double(theme.activeLineNumber.usingColorSpace(.sRGB)?.saturationComponent ?? 0)
        }

        #expect(chosen > raw, "ハイライト色そのままより読みにくい色を選んでいる")
        // ふつうの行番号は灰色なので、色が付いていること自体が見分けの手がかりになる。
        // 明度で比べても意味が無い（琥珀色と灰色は明るさが近い）。
        #expect(saturation > 0.4, "行番号の灰色と見分けが付く色になっていない")
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
}
#endif
