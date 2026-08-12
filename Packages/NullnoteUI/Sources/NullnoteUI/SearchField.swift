import SwiftUI

/// 文書内を検索するための入力欄。ヘッダー（ツールバー）に置く。
///
/// 入力欄・件数・前後への送り・閉じる、の4つだけ。
/// 置換は持たない（同じ語をまとめて直すのは複数選択の役目にする）。
///
/// 状態は持たず、`SearchSession` を持つ側から値と操作を受け取る。
/// 「いま何番目か」の決め方をこのビューに置くと、テストで縛れなくなる。
///
/// **配色をここで指定しない。** 置き場所がツールバーなので、外観は窓から降りてくる。
/// ここで `markdownColorScheme` を重ねると二重指定になる。
public struct MarkdownSearchField: View {

    @Binding private var query: String
    private let countLabel: String
    private let hasMatches: Bool
    private let theme: MarkdownTheme
    private let focus: FocusState<Bool>.Binding
    /// 「焦点を取れ」の合図。値が変わるたびに入力欄へ焦点を移す。
    private let focusGeneration: Int
    private let onNext: () -> Void
    private let onPrevious: () -> Void
    private let onClose: () -> Void

    public init(
        query: Binding<String>,
        countLabel: String,
        hasMatches: Bool,
        theme: MarkdownTheme,
        focus: FocusState<Bool>.Binding,
        focusGeneration: Int = 0,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self._query = query
        self.countLabel = countLabel
        self.hasMatches = hasMatches
        self.theme = theme
        self.focus = focus
        self.focusGeneration = focusGeneration
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onClose = onClose
    }

    public var body: some View {
        HStack(spacing: 6) {
            field
            Text(countLabel)
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color(platform: theme.quote))
                .lineLimit(1)
                // 件数が 1 桁と 2 桁を行き来しても、前後のボタンが動かない幅を確保する。
                .frame(minWidth: 54, alignment: .leading)

            step(systemImage: "chevron.up", help: "前のヒットへ（⌘⇧G）", action: onPrevious)
            step(systemImage: "chevron.down", help: "次のヒットへ（⌘G）", action: onNext)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(platform: theme.quote))
            .help("検索を閉じる（esc）")
            .accessibilityLabel("検索を閉じる")
        }
        // 左だけ余白を足す。
        //
        // ツールバーは項目の背景をカプセル状に敷くが、その左端より内側から
        // 中身が始まってくれない（実測で 2.5pt はみ出していた）。
        // 右端は ✕ ボタンの当たり判定（18pt）がそのまま余白になるので足りている。
        .padding(.leading, 8)
        .dismissesOnEscape(onClose)
    }

    private var field: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Color(platform: theme.marker))

            // ラベルは読み上げ用。画面には出さない（虫めがねで用は足りている）。
            TextField("検索", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(platform: theme.text))
                .focused(focus)
                // 入力の確定（return）で次のヒットへ。
                // `onKeyPress` で return を横取りすると、日本語入力の変換確定まで
                // 奪ってしまう。前へ戻るのは ⌘⇧G とボタンに任せる。
                .onSubmit(onNext)
                .accessibilityLabel("検索")
                .focusFromAppKit(generation: focusGeneration)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(platform: theme.marker))
                .help("検索語を消す")
                .accessibilityLabel("検索語を消す")
            }
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(platform: theme.codeBackground))
        )
        // 窓を狭めたときはここが縮む。件数とボタンは削らない。
        .frame(minWidth: 110, idealWidth: 200, maxWidth: 240)
    }

    private func step(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(platform: hasMatches ? theme.text : theme.marker))
        .disabled(!hasMatches)
        .help(help)
        .accessibilityLabel(help)
    }
}

private extension View {
    /// AppKit の側から焦点を渡す。SwiftUI の焦点指定はツールバーの中まで届かない。
    @ViewBuilder
    func focusFromAppKit(generation: Int) -> some View {
        #if canImport(AppKit)
        background(SearchFieldFocuser(generation: generation).frame(width: 0, height: 0))
        #else
        self
        #endif
    }

    /// esc で閉じる。macOS だけの作法なので、ここで platform 差を吸収する。
    @ViewBuilder
    func dismissesOnEscape(_ action: @escaping () -> Void) -> some View {
        #if os(macOS)
        onExitCommand(perform: action)
        #else
        self
        #endif
    }
}

#if canImport(AppKit)

/// 入力欄に、AppKit の側から焦点を渡す。
///
/// **SwiftUI の `@FocusState` はツールバーの中まで届かない。**
/// ツールバーの項目は本文とは別の階層に載るため、`focused(_:)` を書いても
/// 焦点が移らなかった（⌘F を押しても本文にカーソルが残ったまま）。
///
/// 入力欄の隣に大きさゼロのビューを1枚置き、そこから兄弟の `NSTextField` を
/// 探して first responder にする。
struct SearchFieldFocuser: NSViewRepresentable {

    /// 「いま焦点を取れ」の合図。値が変わるたびに1回だけ効く。
    let generation: Int

    final class Coordinator {
        var applied: Int?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.required, for: .horizontal)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard context.coordinator.applied != generation else { return }
        context.coordinator.applied = generation

        // このビューがまだ窓に載っていないことがある（出した直後）。
        // 描き終わってから探す。
        DispatchQueue.main.async {
            guard let window = view.window, let field = view.enclosingTextField else { return }
            window.makeFirstResponder(field)
        }
    }
}

private extension NSView {
    /// 自分の下にある最初の `NSTextField`。SwiftUI の `TextField` はこれで描かれる。
    var firstTextField: NSTextField? {
        if let field = self as? NSTextField { return field }
        for subview in subviews {
            if let found = subview.firstTextField { return found }
        }
        return nil
    }

    /// 近くにある入力欄。自分から親をたどって探す。
    ///
    /// 窓の全体から探さないのは、ツールバーが本文とは別の階層
    /// （`NSTitlebarContainerView`）に載っていて、たどり方が変わるため。
    /// 段数は区切る。見つからないなら、そもそも置き場所が想定と違う。
    var enclosingTextField: NSTextField? {
        var ancestor = superview
        for _ in 0..<6 {
            guard let current = ancestor else { return nil }
            if let field = current.firstTextField { return field }
            ancestor = current.superview
        }
        return nil
    }
}

#endif
