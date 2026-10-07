#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

/// プレビューに付けた選択の行き来の色（#M0045）が、実際に描かれるか。
///
/// プレビューの背景はインラインコードの札を描くために差し替えてあり
/// （`InlineCodeLayoutManager`）、色はそこを通る。札として描かれて形が崩れたり、
/// 札の方が消えたりしないことを画素で見る。
@Suite("プレビューの選択の色の描き方")
@MainActor
struct SelectionMarkDrawingTests {

    private let theme = MarkdownTheme.standard(appearance: .light)
    /// 塗られていない場所の色。
    private let ground = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
    /// 色を付けたところの色。見分けやすい緑にする（実際は選択の色）。
    private let mark = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)

    private struct Layout {
        let manager: InlineCodeLayoutManager
        let container: NSTextContainer
        let storage: NSTextStorage
    }

    private func layout(_ source: String) -> Layout {
        guard case .paragraph(let text) = PreviewBuilder.build(source, theme: theme).first?.content else {
            fatalError("段落にならない")
        }
        let storage = NSTextStorage(attributedString: PreviewAttributes.make(
            from: text, theme: theme, baseFont: .systemFont(ofSize: theme.fontSize), baseColor: theme.text
        ))
        let manager = InlineCodeLayoutManager()
        manager.theme = theme
        let container = NSTextContainer(size: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return Layout(manager: manager, container: container, storage: storage)
    }

    private func draw(_ laid: Layout, size: NSSize) throws -> NSBitmapImageRep {
        let canvas = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: canvas))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        ground.setFill()
        NSRect(origin: .zero, size: size).fill()
        context.cgContext.translateBy(x: 0, y: size.height)
        context.cgContext.scaleBy(x: 1, y: -1)
        laid.manager.drawBackground(forGlyphRange: laid.manager.glyphRange(for: laid.container), at: .zero)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return canvas
    }

    /// その文字の真ん中の画素の色。
    private func color(at range: NSRange, in laid: Layout, canvas: NSBitmapImageRep) -> NSColor? {
        let glyphs = laid.manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = laid.manager.boundingRect(forGlyphRange: glyphs, in: laid.container)
        return canvas.colorAt(x: Int(rect.midX), y: Int(rect.midY))
    }

    private func isMark(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color.redComponent < 0.05 && color.greenComponent > 0.95 && color.blueComponent < 0.05
    }

    private func isGround(_ color: NSColor?) -> Bool {
        guard let color else { return false }
        return color.redComponent > 0.95 && color.greenComponent < 0.05 && color.blueComponent > 0.95
    }

    @Test("色を付けた文字の背景が塗られる。付けていない文字は塗られない")
    func paintsMarkedText() throws {
        let laid = layout("Cookie には `_ga` という値")
        let string = laid.storage.string as NSString
        let marked = string.range(of: "という")
        laid.manager.addTemporaryAttribute(.backgroundColor, value: mark, forCharacterRange: marked)

        let canvas = try draw(laid, size: NSSize(width: 600, height: 40))
        #expect(isMark(color(at: marked, in: laid, canvas: canvas)))
        #expect(isGround(color(at: string.range(of: "Cookie"), in: laid, canvas: canvas)))
    }

    @Test("インラインコードの札は、色を付けていなければ今までどおり描かれる")
    func badgeStillDrawn() throws {
        let laid = layout("Cookie には `_ga` という値")
        let string = laid.storage.string as NSString
        laid.manager.addTemporaryAttribute(
            .backgroundColor, value: mark, forCharacterRange: string.range(of: "という")
        )

        let canvas = try draw(laid, size: NSSize(width: 600, height: 40))
        let badge = color(at: string.range(of: "_ga"), in: laid, canvas: canvas)
        #expect(!isMark(badge))
        #expect(!isGround(badge))
    }

    @Test("インラインコードに色を付けると、その文字の背景が色で塗られる")
    func paintsMarkedCode() throws {
        let laid = layout("Cookie には `_ga` という値")
        let string = laid.storage.string as NSString
        let code = string.range(of: "_ga")
        laid.manager.addTemporaryAttribute(.backgroundColor, value: mark, forCharacterRange: code)

        let canvas = try draw(laid, size: NSSize(width: 600, height: 40))
        #expect(isMark(color(at: code, in: laid, canvas: canvas)))
    }
}
#endif
