import NullnoteUI
import SwiftUI

struct SettingsView: View {

    @Binding var fontSize: Double
    @Binding var appearance: MarkdownAppearance
    @Binding var showsLineNumbers: Bool
    @Binding var syncsTitleWithFileName: Bool
    @Binding var breaksOnNewline: Bool
    @Binding var indentStyle: IndentStyle
    @Binding var autoLinksURLs: Bool
    @Binding var ignoresWhitespace: Bool
    @Binding var mermaidLightTheme: MermaidTheme
    @Binding var mermaidDarkTheme: MermaidTheme

    /// 設定の窓の幅。
    private static let windowWidth: CGFloat = 460
    /// 各欄の右側（操作と説明文）の幅。**すべての欄で揃える。**
    /// 説明文の長い欄が増えたので広げた（240 → 300。2026-10-02）。
    private static let controlWidth: CGFloat = 300

    var body: some View {
        Form {
            LabeledContent("テーマ") {
                Picker("テーマ", selection: $appearance) {
                    ForEach(MarkdownAppearance.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: Self.controlWidth)
            }

            LabeledContent("編集画面") {
                Toggle("行番号を表示", isOn: $showsLineNumbers)
                    // 札が折り返したとき、2行目が右に寄らないように。
                    // `LabeledContent` の中は右揃えが受け継がれる（説明文と同じ手当て）。
                    .multilineTextAlignment(.leading)
                    .frame(width: Self.controlWidth, alignment: .leading)
            }

            LabeledContent("インデント") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("インデント", selection: $indentStyle) {
                        ForEach(IndentStyle.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("リストの行で Tab を押したときに、1段ぶんとして入れるものです。⇧Tab で戻します。すでに書かれているインデントは、この設定に関係なくそのまま保たれます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.controlWidth, alignment: .leading)
            }

            LabeledContent("リンク") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("URL を自動でリンクにする", isOn: $autoLinksURLs)
                        .multilineTextAlignment(.leading)
                    Text("https:// で始まる URL のあとに空白か改行を打ったとき、または URL だけを貼り付けたときに、[URL](URL) の形に書き換えます。切ってあると、打ったとおりの文字のまま残します。プレビューでは、どちらでもリンクとして表示されます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // `LabeledContent` の中は右揃えが受け継がれる。
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.controlWidth, alignment: .leading)
            }

            LabeledContent("プレビュー") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("普通の改行でも改行する", isOn: $breaksOnNewline)
                        .multilineTextAlignment(.leading)
                    Text("Markdown は行末に半角スペース2つを置いたときだけ改行します。入れておくと、そのままの改行もプレビューで改行になります。本文は書き換えません。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // `LabeledContent` の中は右揃えが受け継がれる。
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.controlWidth, alignment: .leading)
            }

            LabeledContent("図（mermaid）") {
                VStack(alignment: .leading, spacing: 4) {
                    Picker("ライトのとき", selection: $mermaidLightTheme) {
                        ForEach(MermaidTheme.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Picker("ダークのとき", selection: $mermaidDarkTheme) {
                        ForEach(MermaidTheme.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Text("プレビューの図の配色です。拡大して見るときと、画像に書き出すときも同じ配色になります。図の中に %%{init: {'theme': 'forest'}}%% と書いた図は、そちらが優先されます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // `LabeledContent` の中は右揃えが受け継がれる。
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.controlWidth, alignment: .leading)
            }

            LabeledContent("合流") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("空白の違いだけのところは印を出さない", isOn: $ignoresWhitespace)
                        .multilineTextAlignment(.leading)
                    Text("外の道具が同じファイルを直したとき、行の途中の空白の数だけが違うところは、食い違いとして扱いません。行頭のインデントと行末の空白は、意味が変わるのでそのまま比べます。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.controlWidth, alignment: .leading)
            }

            LabeledContent("ファイル名") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("先頭の見出しと同期", isOn: $syncsTitleWithFileName)
                        .multilineTextAlignment(.leading)
                    Text("ファイル名を変えたとき、本文の先頭の見出しも同じ名前にします。見出しが無ければ足します。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // `LabeledContent` の中は右揃えが受け継がれる。
                        // 折り返す説明文はそのままだと右に寄るので、明示的に左へ戻す。
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: Self.controlWidth, alignment: .leading)
            }

            LabeledContent("文字サイズ") {
                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: $fontSize,
                        in: Double(MarkdownTheme.minimumFontSize)...Double(MarkdownTheme.maximumFontSize),
                        step: 1
                    )
                    Text(verbatim: "\(Int(fontSize)) pt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(width: Self.controlWidth)
            }
        }
        .formStyle(.grouped)
        .frame(width: Self.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
    }
}
