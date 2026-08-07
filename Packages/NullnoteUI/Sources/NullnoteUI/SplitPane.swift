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
    private let minimumPaneWidth: CGFloat
    private let theme: MarkdownTheme
    private let leading: Leading
    private let trailing: Trailing

    /// ドラッグ中の一時的な比率。離した時点で `ratio` に反映する。
    @State private var dragging: Double?

    public init(
        ratio: Binding<Double>,
        minimumPaneWidth: CGFloat = 280,
        theme: MarkdownTheme,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self._ratio = ratio
        self.minimumPaneWidth = minimumPaneWidth
        self.theme = theme
        self.leading = leading()
        self.trailing = trailing()
    }

    private static var dividerWidth: CGFloat { 1 }
    /// 掴める幅。線そのものは細いので、当たり判定だけ広げる。
    private static var grabWidth: CGFloat { 10 }

    public var body: some View {
        GeometryReader { geometry in
            let available = max(0, geometry.size.width - Self.dividerWidth)
            let leadingWidth = width(in: available)

            HStack(spacing: 0) {
                leading.frame(width: leadingWidth)
                divider(available: available)
                trailing.frame(width: max(0, available - leadingWidth))
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
        Rectangle()
            .fill(Color(platform: theme.marker).opacity(0.35))
            .frame(width: Self.dividerWidth)
            .frame(width: Self.grabWidth)          // 当たり判定を広げる
            .contentShape(Rectangle())
            .onHover { inside in
                #if canImport(AppKit)
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                #endif
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        guard available > 0 else { return }
                        let base = width(in: available)
                        dragging = Double((base + value.translation.width) / available)
                    }
                    .onEnded { _ in
                        guard available > 0 else { return }
                        ratio = Double(width(in: available) / available)
                        dragging = nil
                    }
            )
    }
}
