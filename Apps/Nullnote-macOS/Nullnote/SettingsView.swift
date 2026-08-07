import NullnoteUI
import SwiftUI

struct SettingsView: View {

    @Binding var fontSize: Double
    @Binding var appearance: MarkdownAppearance
    @Binding var showsLineNumbers: Bool

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

extension MarkdownAppearance {
    var label: String {
        switch self {
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }
}
