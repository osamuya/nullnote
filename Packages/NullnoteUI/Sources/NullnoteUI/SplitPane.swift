import SwiftUI

/// 左右2つに分ける。分割の位置を**比率**で持つ。
///
/// `HSplitView` を使わない理由:
/// - 初期の配分を指定できない（開いた直後の比率が予測できない）
/// - ウインドウの幅を変えると勝手に配分し直す（保っていた比率が失われる）
///
/// 比率で持てば、ウインドウの大きさが変わっても見た目の割合が変わらない。
public struct SplitPane<Leading: View, Trailing: View>: View {

    /// 左側が占める割合。0…1。
    @Binding private var ratio: Double
    /// 右側を出すか。**出していないときも、左側は同じ場所に置いたままにする。**
    /// 入れ替えると SwiftUI が別のビューとみなし、中の `NSTextView` が作り直される。
    private let showsTrailing: Bool
    private let minimumPaneWidth: CGFloat
    private let theme: MarkdownTheme
    private let leading: Leading
    private let trailing: Trailing

    /// ドラッグ中の一時的な比率。離した時点で `ratio` に反映する。
    @State private var dragging: Double?
    /// 掴んだ時点の幅。**動かすたびに測り直さないこと。**
    /// `DragGesture` のずれは掴んだ場所からの通算なので、
    /// いまの幅に足していくと1回動かすたびに二重に効いて飛んでいく。
    @State private var dragBase: CGFloat?

    public init(
        ratio: Binding<Double>,
        showsTrailing: Bool = true,
        minimumPaneWidth: CGFloat = 280,
        theme: MarkdownTheme,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self._ratio = ratio
        self.showsTrailing = showsTrailing
        self.minimumPaneWidth = minimumPaneWidth
        self.theme = theme
        self.leading = leading()
        self.trailing = trailing()
    }

    private static var dividerWidth: CGFloat { PaneDivider.lineWidth }
    private static var grabWidth: CGFloat { PaneDivider.grabWidth }

    public var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.width - (showsTrailing ? Self.dividerWidth : 0))
            let leadingWidth = showsTrailing ? width(in: available) : available

            // **中身の並びは変えない。** 右側を隠すときも、線も右側も置いたまま
            // 幅を 0 にする。`if` で出し入れすると左側の居場所が変わり、
            // SwiftUI が `NSTextView` を作り直して編集画面が一瞬消える。
            HStack(spacing: 0) {
                leading.frame(width: leadingWidth)
                divider(available: available)
                    .frame(width: showsTrailing ? Self.grabWidth : 0)
                    .opacity(showsTrailing ? 1 : 0)
                    .allowsHitTesting(showsTrailing)
                    .clipped()
                trailing
                    .frame(width: max(0, available - leadingWidth))
                    .clipped()
            }
        }
    }

    /// 比率から実際の幅を出す。どちらの側も最小幅を下回らないようにする。
    private func width(in available: CGFloat) -> CGFloat {
        let current = dragging ?? ratio
        let ideal = available * current
        // 両側の最小幅が確保できないほど狭いときは、半分ずつにする。
        guard available >= minimumPaneWidth * 2 else { return available / 2 }
        return min(max(ideal, minimumPaneWidth), available - minimumPaneWidth)
    }

    private func divider(available: CGFloat) -> some View {
        PaneDivider(theme: theme) { translation in
            guard available > 0 else { return }
            let base = dragBase ?? width(in: available)
            dragBase = base
            dragging = Double((base + translation) / available)
        } onEnded: {
            guard available > 0 else { return }
            ratio = Double(width(in: available) / available)
            dragging = nil
            dragBase = nil
        }
    }
}

/// 2つの領域を分ける、掴んで動かせる線。
///
/// 線そのものは細い。**当たり判定だけ外側の幅いっぱいに広げる**ので、
/// 置く側が `.frame(width:)` で掴める幅を決める。
struct PaneDivider: View {

    let theme: MarkdownTheme
    /// 掴んで動かしているあいだ、始点からのずれを渡す。
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    static var lineWidth: CGFloat { 1 }
    /// 掴める幅。
    static var grabWidth: CGFloat { 10 }

    var body: some View {
        Rectangle()
            .fill(Color(platform: theme.marker).opacity(0.35))
            .frame(width: Self.lineWidth)
            .frame(maxWidth: .infinity)            // 当たり判定は外側の幅いっぱい
            .contentShape(Rectangle())
            .onHover { inside in
                #if canImport(AppKit)
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                #endif
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { onChanged($0.translation.width) }
                    .onEnded { _ in onEnded() }
            )
    }
}
