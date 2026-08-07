import NullnoteUI
import SwiftUI

/// 1つの書類を表示する画面。
///
/// 既定では画面がひとつ。ツールバーのボタンで、左に目次、右にプレビューを並べる。
struct DocumentView: View {

    @Binding var document: MarkdownDocument
    let fontSize: Double
    let appearance: MarkdownAppearance

    @State private var showsOutline = false
    @State private var showsPreview = false
    /// エディタで一番上に見えている行。プレビューを追従させるために使う。
    @State private var topVisibleLine = 1
    /// 目次から「ここへ移動して」と伝えるための依頼。
    @State private var scrollRequest: EditorScrollRequest?

    private var theme: MarkdownTheme {
        .standard(fontSize: CGFloat(fontSize), appearance: appearance)
    }

    var body: some View {
        HSplitView {
            if showsOutline {
                OutlineView(source: document.text, theme: theme) { line in
                    scrollRequest = EditorScrollRequest(line: line)
                }
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 400)
            }

            // プレビューを閉じているときは行番号を配らない。
            // スクロールのたびに状態を書き換えても意味が無いため。
            MarkdownEditorView(
                text: $document.text,
                theme: theme,
                topVisibleLine: showsPreview ? $topVisibleLine : nil,
                scrollRequest: scrollRequest
            )
            .frame(minWidth: 280)

            if showsPreview {
                MarkdownPreview(source: document.text, theme: theme, anchorLine: topVisibleLine)
                    .frame(minWidth: 280)
            }
        }
        .frame(minWidth: 480, minHeight: 320)
        // ウインドウ全体（ツールバーやスプリッタも含む）を設定に合わせる。
        .preferredColorScheme(appearance.colorScheme)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Toggle(isOn: $showsOutline.animation(.easeInOut(duration: 0.15))) {
                    Label("目次", systemImage: "sidebar.left")
                }
                .help(showsOutline ? "目次を隠す" : "見出しの目次を表示")
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $showsPreview.animation(.easeInOut(duration: 0.15))) {
                    Label("プレビュー", systemImage: "sidebar.squares.right")
                }
                .help(showsPreview ? "プレビューを隠す" : "プレビューを左右に並べる")
            }
        }
        // メニューやキーボードショートカットから切り替えられるようにする。
        .focusedSceneValue(\.previewVisibility, $showsPreview)
        .focusedSceneValue(\.outlineVisibility, $showsOutline)
    }
}

// MARK: - メニューへの受け渡し

private struct PreviewVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct OutlineVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    /// 前面の書類ウインドウのプレビュー表示状態。
    var previewVisibility: Binding<Bool>? {
        get { self[PreviewVisibilityKey.self] }
        set { self[PreviewVisibilityKey.self] = newValue }
    }

    /// 前面の書類ウインドウの目次表示状態。
    var outlineVisibility: Binding<Bool>? {
        get { self[OutlineVisibilityKey.self] }
        set { self[OutlineVisibilityKey.self] = newValue }
    }
}
