import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// プレビューの本文を描くビュー。
///
/// macOS では `NSTextView` を使う。SwiftUI の `Text` はリンク単位のホバーも
/// カーソルの変更も扱えないため（`docs/02-decision-log.md` の D-13）。
/// iOS では従来どおり `Text` で描く。ホバーという概念が無いので不足しない。
struct PreviewText: View {

    let text: AttributedString
    let theme: MarkdownTheme
    /// 見出しなど、本文と違う字面で描きたいときに渡す。
    var font: PlatformFont
    var color: PlatformColor
    var alignment: TextAlignment = .leading

    init(
        _ text: AttributedString,
        theme: MarkdownTheme,
        font: PlatformFont? = nil,
        color: PlatformColor? = nil,
        alignment: TextAlignment = .leading
    ) {
        self.text = text
        self.theme = theme
        self.font = font ?? .editorBody(size: theme.fontSize)
        self.color = color ?? theme.text
        self.alignment = alignment
    }

    var body: some View {
        #if canImport(AppKit)
        PreviewTextRepresentable(
            attributed: PreviewAttributes.make(
                from: text, theme: theme, baseFont: font, baseColor: color, alignment: alignment
            ),
            theme: theme
        )
        #else
        Text(text)
            .font(.system(size: font.pointSize))
            .foregroundStyle(Color(platform: color))
            .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : (alignment == .trailing ? .trailing : .leading))
        #endif
    }
}

// MARK: - 属性の変換

/// `AttributedString`（意味づけ）を AppKit の属性へ落とす。
///
/// `PreviewModel` は装飾を `inlinePresentationIntent` に載せている。
/// SwiftUI 用に焼き込んだフォントや色は無視して、ここで作り直す。
/// **意味づけを1か所に置き、描画側が解釈する**という形を保つため。
enum PreviewAttributes {

    static func make(
        from text: AttributedString,
        theme: MarkdownTheme,
        baseFont: PlatformFont,
        baseColor: PlatformColor,
        alignment: TextAlignment
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = theme.fontSize * 0.22
        switch alignment {
        case .center: paragraph.alignment = .center
        case .trailing: paragraph.alignment = .right
        default: paragraph.alignment = .natural
        }

        let result = NSMutableAttributedString()

        for run in text.runs {
            let piece = String(text[run.range].characters)
            guard !piece.isEmpty else { continue }

            let intent = run.inlinePresentationIntent ?? []
            var font = baseFont
            var color = baseColor
            var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph]

            if intent.contains(.code) {
                font = .editorMonospaced(size: baseFont.pointSize)
                color = theme.code
                attributes[.backgroundColor] = theme.codeBackground
            }
            font = font.addingTraits(
                bold: intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized)
            )
            if intent.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                attributes[.strikethroughColor] = theme.marker
            }

            // リンクは色・下線・カーソルを NSTextView に任せる（linkTextAttributes）。
            if let url = run.link {
                attributes[.link] = url
            }

            attributes[.font] = font
            attributes[.foregroundColor] = color
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        return result
    }
}

// MARK: - macOS の実装

#if canImport(AppKit)

private struct PreviewTextRepresentable: NSViewRepresentable {

    let attributed: NSAttributedString
    let theme: MarkdownTheme

    func makeNSView(context: Context) -> LinkHoverTextView {
        // レイアウトの寸法を測るため、TextKit 1 で組み立てる。
        // `NSTextView(frame:)` だけだと TextKit 2 になり、`layoutManager` が nil になる。
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = LinkHoverTextView(frame: .zero, textContainer: container)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        apply(theme, to: textView)
        textView.textStorage?.setAttributedString(attributed)
        return textView
    }

    func updateNSView(_ textView: LinkHoverTextView, context: Context) {
        apply(theme, to: textView)
        if textView.textStorage?.isEqual(to: attributed) != true {
            textView.textStorage?.setAttributedString(attributed)
        }
    }

    /// 高さを本文の量に合わせる。これが無いと `VStack` が正しく積めない。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkHoverTextView, context: Context) -> CGSize? {
        guard let container = nsView.textContainer, let layoutManager = nsView.layoutManager else { return nil }
        let width = proposal.width ?? nsView.bounds.width
        guard width > 0, width.isFinite else { return nil }

        container.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container)
        return CGSize(width: width, height: ceil(used.height))
    }

    private func apply(_ theme: MarkdownTheme, to textView: LinkHoverTextView) {
        textView.appearance = theme.appearance.platformAppearance
        textView.linkColor = theme.link
        // 既定の見た目。リンクだと分かるよう、常に下線を引く。
        textView.linkTextAttributes = [
            .foregroundColor: theme.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
    }
}

/// リンクにマウスが乗ったとき、下線を太くして反応を返す。
///
/// `NSTextView` は `.link` 属性があれば、指マークのカーソルとクリックでの
/// URL 起動を自前で面倒みてくれる。ホバーの見た目だけは自分で書く。
final class LinkHoverTextView: NSTextView {

    var linkColor: PlatformColor = .linkColor

    /// いま下線を太くしている範囲。
    private var hoveredRange: NSRange?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        updateHover(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHover()
    }

    private func updateHover(at point: CGPoint) {
        guard let storage = textStorage, storage.length > 0 else { return }

        // 文字が無い余白でも `characterIndexForInsertion` は近くの位置を返す。
        // 実際にその字の上にいるかを、字の矩形で確かめる。
        let index = characterIndexForInsertion(at: point)
        guard index < storage.length,
              let layoutManager, let container = textContainer else { return clearHover() }

        let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
        guard rect.contains(point) else { return clearHover() }

        var effective = NSRange()
        guard storage.attribute(.link, at: index, effectiveRange: &effective) != nil else {
            return clearHover()
        }
        guard effective != hoveredRange else { return }

        clearHover()
        storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, range: effective)
        hoveredRange = effective
    }

    private func clearHover() {
        guard let hoveredRange, let storage = textStorage else { return }
        if NSMaxRange(hoveredRange) <= storage.length {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: hoveredRange)
        }
        self.hoveredRange = nil
    }
}

#endif
