import NullnoteUI
import SwiftUI

struct SettingsView: View {

    @Binding var fontSize: Double
    @Binding var appearance: MarkdownAppearance
    @Binding var showsLineNumbers: Bool
    @Binding var syncsTitleWithFileName: Bool

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
                .frame(width: 240)
            }

            LabeledContent("編集画面") {
                Toggle("行番号を表示", isOn: $showsLineNumbers)
                    .frame(width: 240, alignment: .leading)
            }

            LabeledContent("ファイル名") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("先頭の見出しと同期", isOn: $syncsTitleWithFileName)
                    Text("ファイル名を変えたとき、本文の先頭の見出しも同じ名前にします。見出しが無ければ足します。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        // `LabeledContent` の中は右揃えが受け継がれる。
                        // 折り返す説明文はそのままだと右に寄るので、明示的に左へ戻す。
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 240, alignment: .leading)
            }

            LabeledContent("文字サイズ") {
                VStack(alignment: .leading, spacing: 6) {
                    Slider(
                        value: $fontSize,
                        in: Double(MarkdownTheme.minimumFontSize)...Double(MarkdownTheme.maximumFontSize),
                        step: 1
                    )
                    Text("\(Int(fontSize)) pt")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .frame(width: 240)
            }
        }
        .formStyle(.grouped)
        .frame(width: 400)
        .fixedSize(horizontal: false, vertical: true)
    }
}
