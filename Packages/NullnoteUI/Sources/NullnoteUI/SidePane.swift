import SwiftUI

/// 側に置く一覧（目次）と、その右の本体。
///
/// 幅は**点で持つ**。`SplitPane` の比率と違うのは、側に置く一覧は
/// ウインドウを広げても広がらない方が自然なため。
///
/// **閉じているときも本体の居場所を変えないこと。**
/// `if showsSide { HSplitView { side; content } } else { content }` と書くと、
/// 開け閉めのたびに SwiftUI が本体を別のビューとみなし、中の `NSTextView` を
/// 作り直す。本文の貼り直しと組版が最初からやり直しになり、編集画面が一瞬消える
/// （`SplitPane` で同じことを踏んだ）。
public struct SidePane<Side: View, Content: View>: View {

    /// 側の幅。掴んで動かすとここが変わる。
    @Binding private var width: CGFloat
    private let showsSide: Bool
    private let range: ClosedRange<CGFloat>
    private let theme: MarkdownTheme
    private let side: Side
    private let content: Content

    /// 掴んで動かしているあいだの幅。離した時点で `width` に反映する。
    @State private var dragging: CGFloat?
    /// 掴んだ時点の幅。**動かすたびに測り直さないこと。**
    /// `DragGesture` のずれは掴んだ場所からの通算なので、
    /// いまの幅に足していくと1回動かすたびに二重に効いて飛んでいく。
    @State private var dragBase: CGFloat?

    public init(
        width: Binding<CGFloat>,
        showsSide: Bool,
        range: ClosedRange<CGFloat> = 160...400,
        theme: MarkdownTheme,
        @ViewBuilder side: () -> Side,
        @ViewBuilder content: () -> Content
    ) {
        self._width = width
        self.showsSide = showsSide
        self.range = range
        self.theme = theme
        self.side = side()
        self.content = content()
    }

    private var currentWidth: CGFloat {
        min(max(dragging ?? width, range.lowerBound), range.upperBound)
    }

    public var body: some View {
        // **並びは変えない。** 閉じるときも側と線を置いたまま幅を 0 にする。
        HStack(spacing: 0) {
            // **中身はいつも開いたときの幅で組む。**
            // 外側の幅だけを動かして切り抜く。中身の幅まで動かすと、
            // 開け閉めのあいだ毎フレーム組み直すことになり、
            // 項目が多いほど重くなる（目次で実際に緩慢になった）。
            side
                .frame(width: currentWidth)
                .frame(width: showsSide ? currentWidth : 0, alignment: .trailing)
                .clipped()
            divider
                .frame(width: showsSide ? PaneDivider.grabWidth : 0)
                .opacity(showsSide ? 1 : 0)
                .allowsHitTesting(showsSide)
                .clipped()
            content
                .frame(maxWidth: .infinity)
        }
    }

    private var divider: some View {
        PaneDivider(theme: theme) { translation in
            let base = dragBase ?? currentWidth
            dragBase = base
            dragging = base + translation
        } onEnded: {
            width = currentWidth
            dragging = nil
            dragBase = nil
        }
    }
}
