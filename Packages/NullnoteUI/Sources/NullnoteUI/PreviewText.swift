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
        // 属性の変換はここでは行わない。`body` は再描画のたびに評価されるため、
        // ウインドウのリサイズ中は毎フレーム全ブロックを作り直すことになる。
        // 実際に中身が変わったときだけ変換する（`updateNSView` を参照）。
        PreviewTextRepresentable(
            text: text, theme: theme, baseFont: font, baseColor: color,
            alignment: alignment.textAlignment
        )
        // AppKit のビューはベースラインを持たない。教えないと
        // `HStack(alignment: .firstTextBaseline)` で並べたときにずれる。
        .alignmentGuide(.firstTextBaseline) { [ascender = font.ascender] _ in ascender }
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
        alignment: NSTextAlignment = .natural
    ) -> NSAttributedString {
        // **測定用には必ず `.natural` を渡すこと。**
        // 中央・右揃えにするとグリフがコンテナ幅いっぱいに配置され、
        // 測った幅が実際の文字幅より広くなる。表示用にだけ揃えを入れる。
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = theme.fontSize * 0.22
        paragraph.alignment = alignment

        let result = NSMutableAttributedString()
        /// インラインコードの範囲。あとで前後に隙間を作るために覚えておく。
        var codeRanges: [NSRange] = []

        for run in text.runs {
            var piece = String(text[run.range].characters)
            guard !piece.isEmpty else { continue }

            let intent = run.inlinePresentationIntent ?? []
            var font = baseFont
            var color = baseColor
            var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph]

            if intent.contains(.code) {
                font = .editorMonospaced(size: baseFont.pointSize)
                color = theme.inlineCodeText
                // 角丸の札は `InlineCodeLayoutManager` が描く。
                // ここは「背景色が付いている」ことだけ伝える。
                attributes[.backgroundColor] = theme.inlineCodeBackground
                // 左の余白を作るための、幅ゼロの文字を頭に足す（後述）。
                piece = Self.leadingSpacer + piece
                codeRanges.append(NSRange(location: result.length, length: (piece as NSString).length))
            }
            font = font.addingTraits(
                bold: intent.contains(.stronglyEmphasized),
                italic: intent.contains(.emphasized)
            )
            // 取り消した文字は、線を太くしたうえで文字自体も沈ませる。
            // 細い線を1本引くだけだと、ぱっと見でふつうの文字と区別が付かない。
            if intent.contains(.strikethrough) {
                color = theme.struckText
                attributes[.strikethroughStyle] = NSUnderlineStyle.thick.rawValue
                attributes[.strikethroughColor] = theme.struckText
            }

            // リンクは色・下線・カーソルを NSTextView に任せる（linkTextAttributes）。
            if let url = run.link {
                attributes[.link] = url
            }

            attributes[.font] = font
            attributes[.foregroundColor] = color
            result.append(NSAttributedString(string: piece, attributes: attributes))
        }
        addSpacing(around: codeRanges, in: result, padding: theme.inlineCodePadding)
        return result
    }

    /// 札の左の余白を作るための、幅ゼロの文字。
    ///
    /// **U+2060（WORD JOINER）を使う。** 同じ幅ゼロでも U+200B（ZERO WIDTH SPACE）は
    /// 改行してよい位置として扱われ、札の頭だけが行末に取り残されることがある。
    static let leadingSpacer = "\u{2060}"

    /// インラインコードの前後に余白と隙間を作る。
    ///
    /// **札の矩形を左右に広げる形にはできない。** 文字の位置は変わらないので隣の字にかぶるし、
    /// 行やマスの先頭では左に広げる余地が無く、余白が 0 に潰れる（実際に潰れていた）。
    /// 余白も隙間も、字送りを広げて**実体のある空き**として作る。
    ///
    /// `kern` は「その文字の**後ろ**」に空きを足す。置き場所は3つ。
    ///
    /// ```
    /// あ    ⁠[  code  ]    い
    ///   ↑   ↑        ↑
    ///   隙間 左の余白  右の余白＋隙間
    ///   直前 幅ゼロの   最後の文字（半分は札に、半分は隙間に）
    ///   の字 文字
    /// ```
    ///
    /// 先頭の空きは札の中（幅ゼロの文字）に置くので、**行頭でも潰れない。**
    ///
    /// 測定用の文字列にも同じ処理が入る。入れないと、札のぶんだけ幅が足りなくなる。
    private static func addSpacing(around ranges: [NSRange], in string: NSMutableAttributedString, padding: CGFloat) {
        for range in ranges where range.length > 1 {
            // 直前の字との隙間。
            if range.location > 0 {
                string.addAttribute(.kern, value: padding, range: NSRange(location: range.location - 1, length: 1))
            }
            // 札の中の、左の余白。
            string.addAttribute(.kern, value: padding, range: NSRange(location: range.location, length: 1))
            // 札の中の右の余白と、次の字との隙間。描く側で半分だけ札に取り込む。
            string.addAttribute(.kern, value: padding * 2, range: NSRange(location: NSMaxRange(range) - 1, length: 1))
        }
    }
}

// MARK: - macOS の実装

#if canImport(AppKit)

/// インラインコードを、角丸の札として描くレイアウトマネージャ。
///
/// `NSAttributedString` の `.backgroundColor` は**角の無い矩形**をそのまま塗る。
/// 余白も付かないので、記法文字（バッククォート）が消えたプレビューでは
/// ただの色付きの文字にしか見えない。塗るところだけ差し替える。
///
/// `fillBackgroundRectArray` は AppKit が背景色の続く範囲ごとに呼ぶ。
/// **行をまたぐと矩形が複数渡る**ので、受け取った数だけ描く。
///
/// プレビューで `.backgroundColor` を使うのはインラインコードだけ
/// （コードブロックと表の見出しは SwiftUI 側で敷いている）。
/// ここが増えたら、色で見分けるのではなく専用の属性を足すこと。
final class InlineCodeLayoutManager: NSLayoutManager {

    /// 角丸と余白の寸法を決めるために持つ。設定されるまでは既定の描き方に任せる。
    var theme: MarkdownTheme?

    override func fillBackgroundRectArray(
        _ rectArray: UnsafePointer<NSRect>,
        count: Int,
        forCharacterRange charRange: NSRange,
        color: NSColor
    ) {
        guard let theme else {
            return super.fillBackgroundRectArray(rectArray, count: count, forCharacterRange: charRange, color: color)
        }

        let padding = theme.inlineCodePadding
        let radius = theme.inlineCodeCornerRadius
        color.setFill()
        theme.inlineCodeBorder.setStroke()

        for index in 0..<count {
            var rect = rectArray[index]

            // 左の余白は札の中（幅ゼロの文字）に入っているので、ここでは触らない。
            // 右端に付けた空き（padding * 2）だけ、半分を隣との隙間として残す。
            rect.size.width = max(0, rect.width - padding)

            // 高さは行の高さではなく文字の大きさから決める。行間まで塗ると
            // 札が縦に伸びて、行が詰まって見える。
            let height = min(rect.height, theme.inlineCodeHeight)
            rect.origin.y += ((rect.height - height) / 2).rounded()
            rect.size.height = height

            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

private struct PreviewTextRepresentable: NSViewRepresentable {

    let text: AttributedString
    let theme: MarkdownTheme
    let baseFont: PlatformFont
    let baseColor: PlatformColor
    /// 表の列の揃え。**表示にだけ効かせる。** 測定は常に `.natural` で行う。
    let alignment: NSTextAlignment

    /// 変換結果と、大きさを測るための道具を持つ。
    ///
    /// **測定は表示用のレイアウトとは別立てにする。**
    /// 同じレイアウトを測定にも使うと、測るたびにコンテナの幅を書き換えることになり、
    /// 表示側の折り返し幅が測定時の値に引きずられる。
    /// 表示側は `widthTracksTextView` に任せ、AppKit が自分で幅を追従させる。
    final class Coordinator {
        var appliedText: AttributedString?
        var appliedFontSize: CGFloat = 0
        /// 解決したあとの外観で比べる。`.system` のままでも OS 側が変われば貼り直す。
        var appliedAppearanceName: NSAppearance.Name?
        var appliedAlignment: NSTextAlignment = .natural

        let measuringStorage = NSTextStorage()
        let measuringLayout = NSLayoutManager()
        let measuringContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

        init() {
            measuringContainer.widthTracksTextView = false
            measuringContainer.lineFragmentPadding = 0
            // 遅延レイアウトだと測定時に推定値が返ることがある。
            measuringLayout.allowsNonContiguousLayout = false
            measuringStorage.addLayoutManager(measuringLayout)
            measuringLayout.addTextContainer(measuringContainer)
        }

        /// 与えられた幅で組んだときの高さ。
        func height(fitting width: CGFloat) -> CGFloat {
            measuringContainer.containerSize =
                NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            measuringLayout.ensureLayout(for: measuringContainer)
            return ceil(measuringLayout.usedRect(for: measuringContainer).height)
        }

        /// 折り返さずに1行で並べたときの幅。
        ///
        /// **`NSAttributedString.size()` は使わない。** 実際に組んだときの幅と
        /// 食い違うことがある（インラインコードの頭に入れた幅ゼロの文字の
        /// 字送りが数えられず、表の列が1文字ぶん足りなくなった）。
        /// 高さと同じレイアウトで測れば、必ず表示と一致する。
        var naturalWidth: CGFloat {
            measuringContainer.containerSize =
                NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            measuringLayout.ensureLayout(for: measuringContainer)
            return ceil(measuringLayout.usedRect(for: measuringContainer).width)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 画面に出す方。揃えが入る。
    private var attributed: NSAttributedString {
        PreviewAttributes.make(
            from: text, theme: theme, baseFont: baseFont, baseColor: baseColor, alignment: alignment
        )
    }

    /// 幅と高さを測る方。揃えを入れない。
    private var measuring: NSAttributedString {
        PreviewAttributes.make(from: text, theme: theme, baseFont: baseFont, baseColor: baseColor)
    }

    /// 作り直しが要るか。
    private func needsRebuild(_ coordinator: Coordinator) -> Bool {
        coordinator.appliedText != text
            || coordinator.appliedFontSize != theme.fontSize
            || coordinator.appliedAppearanceName != theme.appearance.platformAppearance.name
            || coordinator.appliedAlignment != alignment
    }

    private func remember(in coordinator: Coordinator) {
        coordinator.appliedText = text
        coordinator.appliedFontSize = theme.fontSize
        coordinator.appliedAppearanceName = theme.appearance.platformAppearance.name
        coordinator.appliedAlignment = alignment
    }

    func makeNSView(context: Context) -> LinkHoverTextView {
        // レイアウトの寸法を測るため、TextKit 1 で組み立てる。
        // `NSTextView(frame:)` だけだと TextKit 2 になり、`layoutManager` が nil になる。
        let storage = NSTextStorage()
        let layoutManager = InlineCodeLayoutManager()
        layoutManager.theme = theme
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
        context.coordinator.measuringStorage.setAttributedString(measuring)
        remember(in: context.coordinator)
        return textView
    }

    func updateNSView(_ textView: LinkHoverTextView, context: Context) {
        guard needsRebuild(context.coordinator) else { return }
        // 文字サイズが変わると角丸と余白の寸法も変わる。渡し直す。
        (textView.layoutManager as? InlineCodeLayoutManager)?.theme = theme
        apply(theme, to: textView)
        textView.textStorage?.setAttributedString(attributed)
        context.coordinator.measuringStorage.setAttributedString(measuring)
        remember(in: context.coordinator)
    }

    /// 本文の量に合わせて大きさを返す。
    ///
    /// 測定は表示用とは別のレイアウトで行う。表示側のコンテナ幅には一切触らない。
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: LinkHoverTextView, context: Context) -> CGSize? {
        let coordinator = context.coordinator

        // 折り返す幅が決まっているとき。
        if let proposed = proposal.width, proposed > 0, proposed.isFinite {
            return CGSize(width: proposed, height: coordinator.height(fitting: proposed))
        }

        // 幅が決まっていないとき（Grid の列幅を決める段階など）は、
        // 折り返さない自然な幅を返す。
        let natural = coordinator.naturalWidth
        return CGSize(width: natural, height: coordinator.height(fitting: natural))
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

#if canImport(AppKit)
extension TextAlignment {
    /// AppKit の行揃えへ。
    var textAlignment: NSTextAlignment {
        switch self {
        case .leading: .natural
        case .center: .center
        case .trailing: .right
        }
    }
}
#endif
