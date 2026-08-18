import NullnoteUI
import SwiftUI

/// 1つの書類を表示する画面。
///
/// 既定では画面がひとつ。ツールバーのボタンで、左に目次、右にプレビューを並べる。
struct DocumentView: View {

    @Binding var document: MarkdownDocument
    /// 書類のファイル。新規で未保存のときは nil。
    let fileURL: URL?
    let fontSize: Double
    let appearance: MarkdownAppearance
    let showsLineNumbers: Bool
    /// ファイル名を変えたとき、本文の先頭の見出しも合わせるか。
    let syncsTitleWithFileName: Bool

    @State private var showsOutline = false
    /// 目次が開け閉めの最中か。ツールバーの輪を回すために持つ。
    @State private var outlineIsBusy = false
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

    /// 外でファイルが書き換わったことを知らせる見張り。
    @State private var watcher: FileWatcher?
    /// 見張りからの知らせ。値が変わるたびに1回、取り込みを検討する。
    @State private var externalChangeCount = 0
    /// 最後に、画面とディスクが一致していた内容。合流の基準にする。
    @State private var lastSyncedText: String?
    /// いま見ているファイル。改名に気づくために、前の値を覚えておく。
    @State private var knownURL: URL?
    /// フォルダに書く許可を、この書類でもう頼んだか。
    @State private var askedForFolderAccess = false
    /// 検索欄に「焦点を取れ」と伝えるための合図。⌘F のたびに増やす。
    @State private var searchFocusGeneration = 0
    /// 検索欄を閉じたとき、編集画面へ焦点を返すための依頼。
    @State private var editorFocusRequest: EditorFocusRequest?
    /// 「同じ語を選んで」の依頼。メニューから来る。
    @State private var editorCommandRequest: EditorCommandRequest?

    /// エディタとプレビューの幅の比率。開いたときは半々。
    /// 中央の線を動かせばその比率を保つ（ウインドウを広げても割合は変わらない）。
    @State private var editorRatio = 0.5
    /// 目次の幅。こちらは比率ではなく点で持つ。
    /// 側に置く一覧はウインドウを広げても広がらない方が自然。
    @State private var outlineWidth: CGFloat = 220

    /// 領域を開け閉めするときの動きの長さ。
    ///
    /// **短くしてある。** 動いているあいだ、エディタは毎フレーム本文を折り返し直す。
    /// 長いほど折り返しの回数が増え、そのぶん引っかかる。
    private static let paneAnimation = 0.1

    private var theme: MarkdownTheme {
        .standard(fontSize: CGFloat(fontSize), appearance: appearance)
    }

    var body: some View {
        VStack(spacing: 0) {
            // **目次の有無で `mainArea` の居場所を変えないこと。**
            // 入れ替えると SwiftUI が別のビューとみなし、`NSTextView` を作り直す
            // （プレビューで踏んだのと同じ。`SidePane` に書いた）。
            SidePane(width: $outlineWidth, showsSide: showsOutline, theme: theme) {
                // 閉じているあいだは中身を作らない。見出しを拾い直し続けても意味が無い。
                if showsOutline {
                    OutlineView(source: document.text, theme: theme) { line in
                        scrollRequest = EditorScrollRequest(line: line)
                    }
                }
            } content: {
                mainArea
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
                Toggle(isOn: outlineVisibility) {
                    // 押したことが伝わるよう、開け閉めのあいだは輪を回す。
                    // **中身は入れ替えない。** 重ねて、不透明度だけ入れ替える
                    // （ツールバーの項目は、中身が変わると取り違えが起きる。下に書いた）。
                    Label("目次", systemImage: "sidebar.left")
                        .opacity(outlineIsBusy ? 0 : 1)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                                .opacity(outlineIsBusy ? 1 : 0)
                        }
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
                Toggle(isOn: $showsPreview.animation(.easeInOut(duration: Self.paneAnimation))) {
                    Label("プレビュー", systemImage: "sidebar.squares.right")
                }
                .help(showsPreview ? "プレビューを隠す" : "プレビューを左右に並べる")
            }
        }
        // メニューやキーボードショートカットから切り替えられるようにする。
        .focusedSceneValue(\.previewVisibility, $showsPreview)
        .focusedSceneValue(\.outlineVisibility, $showsOutline)
        .focusedSceneValue(\.selectionCommands, SelectionCommands(
            selectNext: { editorCommandRequest = EditorCommandRequest(.selectNextOccurrence) },
            selectAll: { editorCommandRequest = EditorCommandRequest(.selectAllOccurrences) }
        ))
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
        // 外でファイルが書き換わったら取り込む。
        // 別のファイルになったとき（改名・別名で保存）も、ここを通る。
        .task(id: fileURL) {
            // **見張りを張り直すのが先。** ここで `lastSyncedText` が
            // ディスクと同じ内容になる。見出しを直すのはそのあと。
            // 逆にすると、直した本文が「ディスクと一致していた内容」として
            // 記録され、次に外の変更が来たときに合流で消される。
            startWatching()
            syncTitleIfRenamed()
            // 次の改名は、いまの名前との差で判断する。
            knownURL = fileURL
        }
        .onChange(of: externalChangeCount) { _, _ in takeInExternalChange() }
    }

    // MARK: - 外の変更を取り込む

    /// ファイルの見張りを張り直す。書類が別のファイルになったときも呼ばれる。
    private func startWatching() {
        watcher?.stop()
        guard let fileURL else {
            watcher = nil
            return
        }
        // いま開いた内容は、ディスクと一致しているはず。ここを基準にする。
        lastSyncedText = document.text
        watcher = FileWatcher(url: fileURL) { externalChangeCount += 1 }
    }

    // MARK: - ファイル名と見出しを揃える

    /// ファイル名が変わっていたら、本文の先頭の見出しも合わせる。
    ///
    /// **開いた直後は何もしない。** 前の名前を知っているときだけ動く。
    /// 新規書類をはじめて保存した場合（`nil` → ファイル）もここには入らない。
    /// 名前を「変えた」のではなく「付けた」場面なので、本文は触らない。
    ///
    /// 直した結果は**保存しない**。未保存の編集として残るので、
    /// 気に入らなければ ⌘Z で戻せて、よければ ⌘S で確定できる。
    private func syncTitleIfRenamed() {
        guard syncsTitleWithFileName else { return }
        guard let previous = knownURL, let fileURL, previous != fileURL else { return }
        guard let updated = TitleSync.applying(
            fileName: fileURL.lastPathComponent, to: document.text
        ) else { return }
        document.text = updated
    }

    /// 見出しに合わせてファイル名を付け直す。
    ///
    /// **保存が済んだときだけ呼ぶ。** 打鍵のたびに改名すると、
    /// 書きかけの名前（「企」「企画」…）でファイルが動き、Finder も git も荒れる。
    ///
    /// **同じ名前のファイルがあるときは何もしない。** 上書きは絶対にしない。
    /// 改名したあとは `fileURL` が変わるので、逆向きの同期（`syncTitleIfRenamed`）が
    /// 走るが、見出しはもう名前と一致しているので何も書き換わらない。
    private func renameFileIfTitleChanged(at fileURL: URL) {
        guard syncsTitleWithFileName else { return }
        guard let name = TitleSync.fileName(
            for: document.text, currentName: fileURL.lastPathComponent
        ) else { return }

        let folder = fileURL.deletingLastPathComponent()
        let destination = folder.appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        // 書類を開いただけでは、その**フォルダ**に書く許可までは付いてこない。
        // 許可が無いまま改名を頼むと、黙って何も起きない（実測: NSCocoaError 513）。
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            askForFolderAccess(to: folder)
            return
        }
        DocumentBridge.rename(at: fileURL, to: destination)
    }

    /// フォルダに書く許可を頼む。**1つの書類につき一度だけ。**
    ///
    /// 断られたあとも聞き続けると、保存のたびにパネルが出る。
    /// 許可が下りたら、その場で付け直しをやり直す。
    private func askForFolderAccess(to folder: URL) {
        guard !askedForFolderAccess else { return }
        askedForFolderAccess = true
        Task { @MainActor in
            guard await FolderAccess.requestWriting(for: folder), let fileURL else { return }
            renameFileIfTitleChanged(at: fileURL)
        }
    }

    /// ディスクの内容を見て、取り込めるなら取り込む。
    ///
    /// **編集中のものがあるときは触らない。** そちらは合流の話になる。
    private func takeInExternalChange() {
        guard let fileURL, let disk = readFromDisk(fileURL) else { return }

        switch ExternalChangeResolver.resolve(
            disk: disk,
            editor: document.text,
            hasLocalEdits: DocumentBridge.hasUnsavedChanges(at: fileURL),
            lastSynced: lastSyncedText
        ) {
        case .ignore:
            // 画面とディスクが一致した。ここが次の合流の基準になる。
            lastSyncedText = disk
            // 一致しているということは、いま保存が済んだところ。
            // 見出しに合わせてファイル名を付け直すのは、この瞬間だけ。
            renameFileIfTitleChanged(at: fileURL)

        case .reload(let text):
            document.text = text
            lastSyncedText = text
            // 本文の差し替えは SwiftUI 側の仕事で、書類の状態が追いつくのは次の周回。
            // 同じ周回で片付けようとすると、こちらの後始末が上書きされる。
            Task { @MainActor in DocumentBridge.acceptExternalContents(at: fileURL) }

        case .merge(let base, let ours, let theirs):
            let result = ThreeWayMerge.merge(base: base, ours: ours, theirs: theirs)
            document.text = result.text
            // 外の内容は取り込んだ（印の中にでも入っている）ので、
            // 次の合流の基準はディスクの側。
            lastSyncedText = theirs
            // **変更の数え上げは戻さない。** 合流の結果はまだ保存されていない。
            // 外で書き換えられたという判定だけ外して、⌘S でそのまま保存できるようにする。
            Task { @MainActor in DocumentBridge.syncModificationDate(at: fileURL) }
        }
    }

    /// 書類を開くときと同じ読み方をする。ここだけ別の解釈にすると化ける。
    private func readFromDisk(_ url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
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
    /// 目次の開け閉め。押したことがすぐ伝わるよう、輪を回してから動かす。
    ///
    /// 幅が変わるあいだ、エディタは本文を折り返し直す。大きな文書ほど時間がかかり、
    /// **押したのに何も起きていないように見えていた。**
    private var outlineVisibility: Binding<Bool> {
        Binding(
            get: { showsOutline },
            set: { wanted in
                outlineIsBusy = true
                withAnimation(.easeInOut(duration: Self.paneAnimation)) { showsOutline = wanted }
                Task {
                    // 動き終わるまで出しておく。少し長めに取って、
                    // 折り返し直しが尾を引いても輪が先に消えないようにする。
                    try? await Task.sleep(for: .milliseconds(320))
                    outlineIsBusy = false
                }
            }
        )
    }

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
                MarkdownPreview(
                    source: document.text,
                    theme: theme,
                    anchorLine: topVisibleLine,
                    documentURL: fileURL
                )
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
            commandRequest: editorCommandRequest,
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

/// 前面の書類ウインドウで、同じ語を選ぶ操作。
struct SelectionCommands {
    let selectNext: () -> Void
    let selectAll: () -> Void
}

private struct SelectionCommandsKey: FocusedValueKey {
    typealias Value = SelectionCommands
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

    /// 前面の書類ウインドウで、同じ語を選ぶ操作。
    var selectionCommands: SelectionCommands? {
        get { self[SelectionCommandsKey.self] }
        set { self[SelectionCommandsKey.self] = newValue }
    }
}
