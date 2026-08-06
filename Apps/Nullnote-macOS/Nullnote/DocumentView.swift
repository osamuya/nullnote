import NullnoteUI
import SwiftUI

/// 1つの書類を表示する画面。
///
/// 既定では画面がひとつ。ツールバーのボタンでプレビューを右に並べる。
struct DocumentView: View {

    @Binding var document: MarkdownDocument
    let fontSize: Double
    let appearance: MarkdownAppearance

    @State private var showsPreview = false
    /// エディタで一番上に見えている行。プレビューを追従させるために使う。
    @State private var topVisibleLine = 1

    private var theme: MarkdownTheme {
        .standard(fontSize: CGFloat(fontSize), appearance: appearance)
    }

    var body: some View {
        Group {
            if showsPreview {
                HSplitView {
                    // プレビューを閉じているときは行番号を配らない。
                    // スクロールのたびに状態を書き換えても意味が無いため。
                    MarkdownEditorView(
                        text: $document.text,
                        theme: theme,
                        topVisibleLine: $topVisibleLine
                    )
                    .frame(minWidth: 280)

                    MarkdownPreview(source: document.text, theme: theme, anchorLine: topVisibleLine)
                        .frame(minWidth: 280)
                }
            } else {
                MarkdownEditorView(text: $document.text, theme: theme)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        // ウインドウ全体（ツールバーやスプリッタも含む）を設定に合わせる。
        .preferredColorScheme(appearance.colorScheme)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showsPreview.animation(.easeInOut(duration: 0.15))) {
                    Label("プレビュー", systemImage: "sidebar.squares.right")
                }
                .help(showsPreview ? "プレビューを隠す" : "プレビューを左右に並べる")
            }
        }
        // メニューやキーボードショートカットから切り替えられるようにする。
        .focusedSceneValue(\.previewVisibility, $showsPreview)
    }
}

// MARK: - メニューへの受け渡し

private struct PreviewVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    /// 前面の書類ウインドウのプレビュー表示状態。
    var previewVisibility: Binding<Bool>? {
        get { self[PreviewVisibilityKey.self] }
        set { self[PreviewVisibilityKey.self] = newValue }
    }
}
