import NullnoteUI
import SwiftUI

@main
struct NullnoteApp: App {

    /// 設定は絞る。増やすときは本当に要るか一度立ち止まること。
    @AppStorage(AppSettings.fontSizeKey)
    private var fontSize: Double = Double(MarkdownTheme.defaultFontSize)

    @AppStorage(AppSettings.appearanceKey)
    private var appearance: MarkdownAppearance = .system

    @AppStorage(AppSettings.lineNumbersKey)
    private var showsLineNumbers = false

    @AppStorage(AppSettings.titleSyncKey)
    private var syncsTitleWithFileName = false

    @AppStorage(AppSettings.breaksOnNewlineKey)
    private var breaksOnNewline = false
    @AppStorage(AppSettings.indentStyleKey)
    private var indentStyle: IndentStyle = .fourSpaces

    init() {
        AppSettings.registerDefaults()
        // 前に許可をもらったフォルダを、また読めるようにする。
        MainActor.assumeIsolated { FolderAccess.restoreAll() }
    }

    /// ボタンやトグルの色。
    ///
    /// **OS のアクセントカラーに従わせない。** 従わせると、利用者の設定しだいで
    /// ツールバーのボタンの色が変わる。配色を1組に決めている以上、ここも自分で持つ。
    private var control: Color {
        Color(platform: MarkdownTheme.standard(appearance: appearance).control)
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(
                document: file.$document,
                fileURL: file.fileURL,
                fontSize: fontSize,
                appearance: appearance,
                showsLineNumbers: showsLineNumbers,
                syncsTitleWithFileName: syncsTitleWithFileName,
                breaksOnNewline: breaksOnNewline,
                indentStyle: indentStyle
            )
            .tint(control)
            // 画像が読めなかったときに、フォルダの閲覧を頼めるようにする。
            .imageAccessRequester(ImageAccessRequester { folder in
                await FolderAccess.request(for: folder)
            })
        }
        .commands {
            CommandGroup(after: .sidebar) {
                ToggleOutlineButton()
                TogglePreviewButton()
                Divider()
            }
            // 検索は編集メニューの、カット・コピー・ペーストの下。macOS の定位置。
            CommandGroup(after: .pasteboard) {
                Divider()
                FindButtons()
                Divider()
                SelectionButtons()
            }
            CommandGroup(after: .textEditing) {
                Divider()
                Button("文字を大きく") {
                    fontSize = min(fontSize + 1, Double(MarkdownTheme.maximumFontSize))
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("文字を小さく") {
                    fontSize = max(fontSize - 1, Double(MarkdownTheme.minimumFontSize))
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("文字サイズを戻す") {
                    fontSize = Double(MarkdownTheme.defaultFontSize)
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }

        Settings {
            SettingsView(
                fontSize: $fontSize,
                appearance: $appearance,
                showsLineNumbers: $showsLineNumbers,
                syncsTitleWithFileName: $syncsTitleWithFileName,
                breaksOnNewline: $breaksOnNewline,
                indentStyle: $indentStyle
            )
            .tint(control)
        }
    }
}

private struct ToggleOutlineButton: View {

    @FocusedValue(\.outlineVisibility) private var visibility

    var body: some View {
        Button(visibility?.wrappedValue == true ? "目次を隠す" : "目次を表示") {
            visibility?.wrappedValue.toggle()
        }
        .keyboardShortcut("s", modifiers: [.control, .command])
        .disabled(visibility == nil)
    }
}

/// 検索・次を検索・前を検索。
///
/// 3つとも前面のウインドウの検索状態に触るので、1つの `View` にまとめて
/// `@FocusedValue` を1回だけ読む。
private struct FindButtons: View {

    @FocusedValue(\.searchCommands) private var commands

    var body: some View {
        Button("検索…") { commands?.open() }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(commands == nil)

        Button("次を検索") { commands?.next() }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(commands?.hasMatches != true)

        Button("前を検索") { commands?.previous() }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(commands?.hasMatches != true)
    }
}

/// 同じ語を選ぶ。置換の代わりに使う。
private struct SelectionButtons: View {

    @FocusedValue(\.selectionCommands) private var commands

    var body: some View {
        Button("同じ語を選ぶ") { commands?.selectNext() }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(commands == nil)

        Button("同じ語を全部選ぶ") { commands?.selectAll() }
            .keyboardShortcut("g", modifiers: [.control, .command])
            .disabled(commands == nil)
    }
}

private struct TogglePreviewButton: View {

    @FocusedValue(\.previewVisibility) private var visibility

    var body: some View {
        Button(visibility?.wrappedValue == true ? "プレビューを隠す" : "プレビューを表示") {
            visibility?.wrappedValue.toggle()
        }
        .keyboardShortcut("p", modifiers: [.command, .shift])
        .disabled(visibility == nil)
    }
}
