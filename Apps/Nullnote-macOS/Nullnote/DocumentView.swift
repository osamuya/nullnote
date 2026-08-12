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

    /// 検索の帯を出しているか。
    @State private var showsSearch = false
    /// 検索語・ヒットの一覧・いま何番目か。
    @State private var search = SearchSession()
    /// 検索から「このヒットを見せて」と伝えるための依頼。
    @State private var selectionRequest: EditorSelectionRequest?
    @FocusState private var searchFocused: Bool
    /// 検索欄に「焦点を取れ」と伝えるための合図。⌘F のたびに増やす。
    @State private var searchFocusGeneration = 0
    /// 検索欄を閉じたとき、編集画面へ焦点を返すための依頼。
    @State private var editorFocusRequest: EditorFocusRequest?

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
            // 検索欄は 🔍 の左に伸びる。出していないときは幅を 0 にして畳む。
            //
            // **項目を出し入れしない。中身を空にもしない。** どちらも効かなかった:
            // - `if showsSearch { ToolbarItem(...) }` … 項目が増減すると SwiftUI が
            //   後続の項目を取り違える（🔍 を押すとプレビューが消えた）
            // - `ToolbarItem { Group { if showsSearch { ... } } }` … 中身が空の状態で
            //   組まれた項目は、あとから中身を入れても現れない
            // 常に同じ中身を置き、幅と不透明度だけ変える。
            ToolbarItem(placement: .primaryAction) {
                searchField
                    .frame(width: showsSearch ? nil : 0)
                    .opacity(showsSearch ? 1 : 0)
                    .disabled(!showsSearch)
                    .clipped()
                    .accessibilityHidden(!showsSearch)
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: searchVisibility) {
                    Label("検索", systemImage: "magnifyingglass")
                }
                .help(showsSearch ? "検索を閉じる" : "文書内を検索（⌘F）")
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
        .focusedSceneValue(\.searchCommands, SearchCommands(
            open: openSearch,
            next: { move { $0.moveToNext() } },
            previous: { move { $0.moveToPrevious() } },
            hasMatches: search.currentRange != nil
        ))
        // 本文が変わったらヒットを数え直す。**移動はしない。**
        // 打鍵のたびに画面が飛ぶのを避けるため、送るのは操作したときだけ。
        .onChange(of: document.text) { _, source in
            guard showsSearch else { return }
            search.refresh(in: source)
        }
        // 検索語が変わったら数え直して、そのヒットを見せる。
        // 検索欄は畳んだ状態でも居続けるので、監視はこちら（本体）に置く。
        .onChange(of: search.query) { _, _ in
            search.refresh(in: document.text)
            showCurrentMatch()
        }
        // 入力欄が有効になってから焦点を移す。
        .onChange(of: showsSearch) { _, shown in
            if shown { searchFocused = true }
        }
    }

    // MARK: - 検索

    private var searchField: some View {
        MarkdownSearchField(
            query: $search.query,
            countLabel: search.countLabel,
            hasMatches: search.currentRange != nil,
            theme: theme,
            focus: $searchFocused,
            focusGeneration: searchFocusGeneration,
            onNext: { move { $0.moveToNext() } },
            onPrevious: { move { $0.moveToPrevious() } },
            onClose: closeSearch
        )
    }

    /// ツールバーの 🔍 が読み書きする値。
    ///
    /// `$showsSearch` を直に渡さない。出すときは入力欄へ焦点を移し、
    /// 閉じるときはハイライトも消す必要があり、素の代入では足りないため。
    private var searchVisibility: Binding<Bool> {
        Binding(
            get: { showsSearch },
            set: { wanted in wanted ? openSearch() : closeSearch() }
        )
    }

    /// 検索欄を出す。すでに出ているときは入力欄へ戻すだけ。
    ///
    /// 出すときにここで焦点を移さないのは、畳んでいるあいだ入力欄を
    /// `disabled` にしてあるため。同じ呼び出しの中で焦点を指定しても、
    /// まだ無効なので効かない。描き直しのあとに移す（`onChange`）。
    private func openSearch() {
        // 合図を増やすと、入力欄が AppKit の側から焦点を取りに行く。
        searchFocusGeneration += 1
        guard !showsSearch else {
            searchFocused = true
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) { showsSearch = true }
    }

    private func closeSearch() {
        withAnimation(.easeInOut(duration: 0.15)) { showsSearch = false }
        searchFocused = false
        // ハイライトも一緒に消す。閉じたのに色が残っていると、
        // 何が塗られているのか分からなくなる。
        search = SearchSession()
        selectionRequest = nil
        // 焦点を編集画面へ返す。返さないと、閉じたあと打っても本文に入らない。
        // カーソルは検索で降りた場所のまま。そこから続けて直せる。
        editorFocusRequest = EditorFocusRequest()
    }

    /// 前後へ送って、そのヒットを見せる。
    private func move(_ step: (inout SearchSession) -> Void) {
        step(&search)
        showCurrentMatch()
    }

    private func showCurrentMatch() {
        guard let range = search.currentRange else { return }
        selectionRequest = EditorSelectionRequest(range: range)
    }

    /// エディタと、開いていればプレビュー。
    /// **プレビューの有無で `editor` の居場所を変えないこと。**
    /// `if showsPreview { SplitPane { editor } } else { editor }` と書くと、
    /// 切り替えたときに SwiftUI が別のビューとみなし、`NSTextView` を作り直す。
    /// 本文の貼り直しと組版が最初からやり直しになり、編集画面が一瞬消える。
    private var mainArea: some View {
        SplitPane(ratio: $editorRatio, showsTrailing: showsPreview, theme: theme) {
            editor
        } trailing: {
            // 閉じているあいだは中身を作らない。作ると解析と NSTextView の
            // 組み立てが動き続ける（表の多い文書ではマスの数だけ増える）。
            if showsPreview {
                MarkdownPreview(source: document.text, theme: theme, anchorLine: topVisibleLine)
            }
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
            selectionRequest: selectionRequest,
            searchHighlight: showsSearch ? search.highlight : nil,
            focusRequest: editorFocusRequest,
            showsLineNumbers: showsLineNumbers
        )
    }
}

// MARK: - メニューへの受け渡し

/// 前面の書類ウインドウの検索操作。
///
/// 「いま何番目か」の計算はウインドウ側（`SearchSession`）に置いたまま、
/// メニューへは呼び出し口だけを渡す。メニュー側に状態を持たせない。
struct SearchCommands {
    let open: () -> Void
    let next: () -> Void
    let previous: () -> Void
    /// 送り先があるか。無いときは「次を検索」「前を検索」を灰色にする。
    let hasMatches: Bool
}

private struct PreviewVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct OutlineVisibilityKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct SearchCommandsKey: FocusedValueKey {
    typealias Value = SearchCommands
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

    /// 前面の書類ウインドウの検索操作。
    var searchCommands: SearchCommands? {
        get { self[SearchCommandsKey.self] }
        set { self[SearchCommandsKey.self] = newValue }
    }
}
