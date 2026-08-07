#if canImport(AppKit)
import AppKit

/// エディタの左端に行番号を描く。
///
/// `NSScrollView` の定規（ruler）として付ける。スクロールへの追従は
/// `NSRulerView` が面倒をみてくれるので、描くものだけを書けばよい。
///
/// **折り返した行には番号を振らない。** 論理行の先頭にあたる行だけに振る。
/// 判定には `LineIndex`（行頭の文字位置の索引）をそのまま使う。
final class LineNumberRulerView: NSRulerView {

    var theme: MarkdownTheme {
        didSet { needsDisplay = true }
    }

    /// 行頭の位置。本文が変わったら差し替える。
    var lineIndex: LineIndex {
        didSet { needsDisplay = true }
    }

    private var textView: NSTextView? { clientView as? NSTextView }

    init(scrollView: NSScrollView, textView: NSTextView, theme: MarkdownTheme) {
        self.theme = theme
        self.lineIndex = LineIndex(textView.string)
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        updateThickness()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("使わない") }

    /// 桁数に合わせて幅を決める。行が増えて桁が上がっても数字が切れない。
    func updateThickness() {
        let digits = max(2, String(lineIndex.lineCount).count)
        let sample = String(repeating: "0", count: digits)
        let width = (sample as NSString).size(withAttributes: [.font: font]).width
        let wanted = ceil(width) + Self.leadingPadding + Self.trailingPadding
        if abs(ruleThickness - wanted) > 0.5 {
            ruleThickness = wanted
        }
    }

    private static let leadingPadding: CGFloat = 8
    private static let trailingPadding: CGFloat = 8

    private var font: NSFont {
        .monospacedDigitSystemFont(ofSize: max(9, theme.fontSize * 0.82), weight: .regular)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        let mode = ProcessInfo.processInfo.environment["RULER_MODE"] ?? "all"
        if mode == "none" { return }
        if mode == "dump" { print("  bounds=\(bounds) rect=\(rect) clip=\(NSGraphicsContext.current?.cgContext.boundingBoxOfClipPath ?? .zero)"); return }
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        // 背景。本文と同じ色にして、境目に細い線だけ引く。
        theme.background.setFill()
        rect.fill()
        theme.marker.withAlphaComponent(0.25).setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.marker,
        ]

        if mode == "bg" { return }
        let visible = scrollView?.contentView.bounds ?? .zero
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: container)
        let inset = textView.textContainerInset.height
        let relativeY = convert(NSPoint.zero, from: textView).y

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragmentGlyphRange, _ in
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)

            // 折り返しでできた断片には番号を振らない。
            // 論理行の先頭と位置が一致するときだけ描く。
            let line = self.lineIndex.line(atUTF16Offset: characterIndex)
            guard self.lineIndex.utf16Offset(ofLine: line) == characterIndex else { return }

            let label = NSAttributedString(string: String(line), attributes: attributes)
            let size = label.size()
            let y = usedRect.minY + relativeY + inset + (usedRect.height - size.height) / 2
            label.draw(at: NSPoint(x: self.bounds.width - size.width - Self.trailingPadding, y: y))
        }
    }
}
#endif
