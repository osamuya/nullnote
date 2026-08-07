#if canImport(AppKit)
import AppKit

/// エディタの左余白に行番号を描く。
///
/// **`NSRulerView` は使わない。** スクロールビューに定規を付けると、AppKit が
/// 定規の右端をなぞる細い縦線をタイトルバーの中まで描き、閉じるボタンの脇を
/// 通ってしまう（決定記録の B-11）。`titlebarSeparatorStyle` では消せなかった。
///
/// **スクロールビューに自前のビューを足す形でもない。** 本文を右へずらすのに
/// `contentInsets` を使うと、SwiftUI がまだ大きさを決めていない時点で
/// テキストコンテナの幅が潰れ、本文が消える（決定記録の D-14 と同じ罠）。
///
/// 代わりに、テキストビュー自身の左右の余白（`textContainerInset`）を広げ、
/// その左側へ番号を描く。番号は本文と同じ座標系にあるので、
/// スクロールへの追従も行の位置合わせも AppKit 任せで済む。
///
/// **折り返した行には番号を振らない。** 論理行の先頭にあたる行だけに振る。
/// 判定には `LineIndex`（行頭の文字位置の索引）をそのまま使う。
struct LineNumberGutter {

    var theme: MarkdownTheme
    /// 行頭の位置。本文が変わったら差し替える。
    var lineIndex: LineIndex

    /// 行番号とは関係なく本文の左右に空ける余白。
    static let textPadding: CGFloat = 12
    private static let leadingPadding: CGFloat = 8
    private static let trailingPadding: CGFloat = 8

    private var font: NSFont {
        .monospacedDigitSystemFont(ofSize: max(9, theme.fontSize * 0.82), weight: .regular)
    }

    /// 桁数に合わせた帯の幅。行が増えて桁が上がっても数字が切れない。
    var width: CGFloat {
        let digits = max(2, String(lineIndex.lineCount).count)
        let sample = String(repeating: "0", count: digits)
        let size = (sample as NSString).size(withAttributes: [.font: font])
        return ceil(size.width) + Self.leadingPadding + Self.trailingPadding
    }

    /// テキストビューに設定すべき左右の余白。
    var textContainerInsetWidth: CGFloat { width + Self.textPadding }

    /// `textView` の座標系に描く。`drawBackground(in:)` から呼ぶ。
    @MainActor
    func draw(in rect: NSRect, of textView: NSTextView, activeLine: Int?) {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer
        else { return }

        // 背景は本文と同じ色。境目に細い線だけ引く。
        // **塗る範囲は帯の幅に閉じ込める。** 広げると本文まで消える（決定記録の B-9）。
        theme.background.setFill()
        NSRect(x: 0, y: rect.minY, width: width, height: rect.height).fill()
        theme.marker.withAlphaComponent(0.25).setFill()
        NSRect(x: width - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: theme.marker,
        ]
        let activeAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .bold),
            .foregroundColor: theme.activeLineNumber,
        ]

        let origin = textView.textContainerOrigin
        let glyphRange = layoutManager.glyphRange(forBoundingRect: rect, in: container)

        func drawNumber(_ line: Int, in usedRect: NSRect) {
            let label = NSAttributedString(
                string: String(line),
                attributes: line == activeLine ? activeAttributes : attributes
            )
            let size = label.size()
            let y = usedRect.minY + origin.y + (usedRect.height - size.height) / 2
            label.draw(at: NSPoint(x: width - size.width - Self.trailingPadding, y: y))
        }

        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, fragmentGlyphRange, _ in
            let characterIndex = layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)

            // 折り返しでできた断片には番号を振らない。
            // 論理行の先頭と位置が一致するときだけ描く。
            let line = lineIndex.line(atUTF16Offset: characterIndex)
            guard lineIndex.utf16Offset(ofLine: line) == characterIndex else { return }
            drawNumber(line, in: usedRect)
        }

        // 末尾が改行のとき、その後ろの空行。
        //
        // `enumerateLineFragments` はこの行を渡してこない（グリフが1つも無いため）。
        // しかしカーソルは置けるし、`LineIndex` もフッターの行数も1行として数える。
        // ここで描かないと、行番号だけ1つ少なくなって食い違う。
        if layoutManager.extraLineFragmentTextContainer != nil {
            let usedRect = layoutManager.extraLineFragmentUsedRect
            if usedRect.offsetBy(dx: 0, dy: origin.y).intersects(rect) {
                drawNumber(lineIndex.lineCount, in: usedRect)
            }
        }
    }
}
#endif
