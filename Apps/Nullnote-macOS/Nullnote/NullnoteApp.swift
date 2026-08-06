import NullnoteUI
import SwiftUI

@main
struct NullnoteApp: App {

    /// 設定は絞る。増やすときは本当に要るか一度立ち止まること。
    @AppStorage(AppSettings.fontSizeKey)
    private var fontSize: Double = Double(MarkdownTheme.defaultFontSize)

    @AppStorage(AppSettings.appearanceKey)
    private var appearance: MarkdownAppearance = .system

    init() {
        AppSettings.registerDefaults()
    }

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            DocumentView(document: file.$document, fontSize: fontSize, appearance: appearance)
        }
        .commands {
            CommandGroup(after: .sidebar) {
                TogglePreviewButton()
                Divider()
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
            SettingsView(fontSize: $fontSize, appearance: $appearance)
        }
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
