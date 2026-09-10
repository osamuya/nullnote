#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

/// インラインコードの札の描き方。
///
/// 札が**次の行へ続くとき**、AppKit は背景の矩形を行の端まで伸ばして渡してくる。
/// そのまま塗ると、文字の無い余白にまで枠と背景が出る（#027）。
/// 画素で見て、文字の右端より先が塗られていないことを縛る。
@Suite("インラインコードの札")
@MainActor
struct InlineCodeBadgeTests {

    private let theme = MarkdownTheme.standard(appearance: .light)

    /// 塗られていない場所の色。札にも文字にも使わない色を敷いて、はみ出しを見つける。
    private let ground = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)

    /// 組んだ結果。**記憶域も返す。**
    ///
    /// `NSLayoutManager` は `NSTextStorage` を弱く参照する。手放すと組版ごと消えて、
    /// 行が1つも取れなくなる（実際にそうなった）。
    private struct Layout {
        let manager: InlineCodeLayoutManager
        let container: NSTextContainer
        let storage: NSTextStorage
    }

    /// 折り返すほど長い札を、与えた幅で組む。
    private func layout(width: CGFloat) -> Layout {
        var text = AttributedString("（ ")
        var code = AttributedString("http://192.168.228.177:8124/logout")
        code.inlinePresentationIntent = .code
        text.append(code)
        text.append(AttributedString(" ）"))

        let storage = NSTextStorage(attributedString: PreviewAttributes.make(
            from: text,
            theme: theme,
            baseFont: .systemFont(ofSize: theme.fontSize),
            baseColor: theme.text
        ))
        let manager = InlineCodeLayoutManager()
        manager.theme = theme
        let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        return Layout(manager: manager, container: container, storage: storage)
    }

    /// 札の背景だけを描いて、画素を取り出す。
    ///
    /// **上下を反転させた文脈に描く。** 組版の座標は下向きに増えるので、
    /// そのまま描くと画像が逆さまになり、行の位置と画素の行が合わない。
    private func draw(
        _ manager: InlineCodeLayoutManager,
        in container: NSTextContainer,
        size: NSSize
    ) throws -> NSBitmapImageRep {
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
        manager.drawBackground(forGlyphRange: manager.glyphRange(for: container), at: .zero)

        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return canvas
    }

    /// その画素の行で、地の色でない一番右の位置。何も塗られていなければ `nil`。
    private func rightmostPainted(in canvas: NSBitmapImageRep, y: Int) -> Int? {
        var found: Int?
        for x in 0..<canvas.pixelsWide {
            guard let color = canvas.colorAt(x: x, y: y) else { continue }
            let isGround = abs(color.redComponent - 1) < 0.02
                && abs(color.greenComponent) < 0.02
                && abs(color.blueComponent - 1) < 0.02
            if !isGround { found = x }
        }
        return found
    }

    @Test("狭い幅では、札が2行にまたがる")
    func badgeWrapsWhenNarrow() {
        let laid = layout(width: 180)
        let (manager, container) = (laid.manager, laid.container)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, _, _, _, _ in
            lines += 1
        }
        #expect(lines >= 2, "折り返していない。この幅では試験にならない")
    }

    @Test("折り返した行で、文字の右端より先を塗らない")
    func doesNotPaintPastTheText() throws {
        let width: CGFloat = 180
        let laid = layout(width: width)
        let (manager, container) = (laid.manager, laid.container)

        // 1行目の、文字が実際に使っている右端。
        var used: NSRect = .zero
        var fragment: NSRect = .zero
        manager.enumerateLineFragments(
            forGlyphRange: manager.glyphRange(for: container)
        ) { rect, usedRect, _, _, stop in
            fragment = rect
            used = usedRect
            stop.pointee = true
        }

        let canvas = try draw(manager, in: container, size: NSSize(width: width, height: 120))
        let middle = Int(fragment.midY)
        let painted = try #require(
            rightmostPainted(in: canvas, y: middle), "1行目に札が描かれていない"
        )

        // **枠は文字の右端で終わる。** 行の端（180）まで伸びていたのが #027。
        #expect(
            CGFloat(painted) <= used.maxX + 2,
            "文字の右端 \(Int(used.maxX)) より先の \(painted) まで塗られている"
        )
    }

    @Test("折り返しの途中の行でも、本文が欠けない")
    func doesNotClipTheFirstLine() throws {
        let width: CGFloat = 180
        let laid = layout(width: width)
        let (manager, container) = (laid.manager, laid.container)

        var used: NSRect = .zero
        var fragment: NSRect = .zero
        manager.enumerateLineFragments(
            forGlyphRange: manager.glyphRange(for: container)
        ) { rect, usedRect, _, _, stop in
            fragment = rect
            used = usedRect
            stop.pointee = true
        }

        let canvas = try draw(manager, in: container, size: NSSize(width: width, height: 120))
        let painted = try #require(rightmostPainted(in: canvas, y: Int(fragment.midY)))

        // 右の空き（padding * 2）は札の**最後の文字**に付いている。
        // 折り返した途中の行には無いので、そこで削ると最後の文字が枠からはみ出す。
        // **削り幅（\(Int(theme.inlineCodePadding)) 画素）より狭い許容にすること。**
        // 緩いと、削ってしまっても気づけない。
        #expect(
            CGFloat(painted) >= used.maxX - 2,
            "文字の右端 \(Int(used.maxX)) に対して \(painted) までしか塗られていない"
        )
    }

    @Test("折り返さない札は、これまでどおり文字を囲む")
    func wrapsTightlyWhenItFits() throws {
        let width: CGFloat = 600
        let laid = layout(width: width)
        let (manager, container) = (laid.manager, laid.container)

        var used: NSRect = .zero
        var fragment: NSRect = .zero
        manager.enumerateLineFragments(
            forGlyphRange: manager.glyphRange(for: container)
        ) { rect, usedRect, _, _, stop in
            fragment = rect
            used = usedRect
            stop.pointee = true
        }

        let canvas = try draw(manager, in: container, size: NSSize(width: width, height: 120))
        let painted = try #require(rightmostPainted(in: canvas, y: Int(fragment.midY)))

        // 札のあとに「 ）」が続くので、塗りは文字の右端よりだいぶ手前で終わる。
        #expect(CGFloat(painted) < used.maxX)
        #expect(painted > 0)
    }
}
#endif
