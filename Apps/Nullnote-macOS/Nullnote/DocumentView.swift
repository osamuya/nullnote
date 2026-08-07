import NullnoteUI
import SwiftUI

/// 1つの書類を表示する画面。
///
/// 既定では画面がひとつ。ツールバーのボタンで、左に目次、右にプレビューを並べる。
struct DocumentView: View {

    @Binding var document: MarkdownDocument
    let fontSize: Double
    let appearance: MarkdownAppearance
    let showsLineNumbers: Bool

    @State private var showsOutline = false
    @State private var showsPreview = false
    /// エディタで一番上に見えている行。プレビューを追従させるために使う。
    @State private var topVisibleLine = 1
    /// 目次から「ここへ移動して」と伝えるための依頼。
    @State private var scrollRequest: EditorScrollRequest?

    /// エディタとプレビューの幅の比率。開いたときは半々。
    /// 中央の線を動かせばその比率を保つ（ウインドウを広げても割合は変わらない）。
    @State private var editorRatio = 0.5
    /// 目次の幅。こちらは比率ではなく点で持つ。
    /// 側に置く一覧はウインドウを広げても広がらない方が自然。
    @State private var outlineWidth: CGFloat = 220

    private var theme: MarkdownTheme {
        .standard(fontSize: CGFloat(fontSize), appearance: appearance)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if showsOutline {
                    HSplitView {
                        OutlineView(source: document.text, theme: theme) { line in
                            scrollRequest = EditorScrollRequest(line: line)
                        }
                        .frame(minWidth: 160, idealWidth: outlineWidth, maxWidth: 400)

                        mainArea
                    }
                } else {
                    mainArea
                }
            }
            // 目次もプレビューも含めた窓の一番下に置く。
            MarkdownStatusBar(source: document.text, theme: theme)
        }
        .frame(minWidth: 480, minHeight: 320)
        // ウインドウ全体（ツールバーやスプリッタも含む）を設定に合わせる。
        .markdownColorScheme(appearance)
        // ヘッダは列ごとに切れず、窓の幅いっぱいに1本の帯として出す。
        .toolbarBackground(.visible, for: .windowToolbar)
        .straightHeader()
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

    /// エディタと、開いていればプレビュー。
    @ViewBuilder
    private var mainArea: some View {
        if showsPreview {
            SplitPane(ratio: $editorRatio, theme: theme) {
                editor
            } trailing: {
                MarkdownPreview(source: document.text, theme: theme, anchorLine: topVisibleLine)
            }
        } else {
            editor
        }
    }

    private var editor: some View {
        // プレビューを閉じているときは行番号を配らない。
        // スクロールのたびに状態を書き換えても意味が無いため。
        MarkdownEditorView(
            text: $document.text,
            theme: theme,
            topVisibleLine: showsPreview ? $topVisibleLine : nil,
            scrollRequest: scrollRequest,
            showsLineNumbers: showsLineNumbers
        )
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
