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
    private let onNext: () -> Void
    private let onPrevious: () -> Void
    private let onClose: () -> Void

    public init(
        query: Binding<String>,
        countLabel: String,
        hasMatches: Bool,
        theme: MarkdownTheme,
        focus: FocusState<Bool>.Binding,
        onNext: @escaping () -> Void,
        onPrevious: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self._query = query
        self.countLabel = countLabel
        self.hasMatches = hasMatches
        self.theme = theme
        self.focus = focus
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
