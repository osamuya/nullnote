import SwiftUI

/// 画面の下端に出す小さな情報の帯。
///
/// 今どういう設定で書いているか（テーマ・文字サイズ）と、
/// 書いているものの大きさ（行数・バイト数）を右寄せで並べる。
///
/// **文字コードは出さない。** 読み書きとも UTF-8 に固定していて選べないため、
/// 出しても判断の材料にならない。
public struct MarkdownStatusBar: View {

    let source: String
    let theme: MarkdownTheme
    /// 文字サイズを選んだときに呼ぶ。nil なら、文字サイズは表示するだけ。
    let selectFontSize: ((CGFloat) -> Void)?

    public init(source: String, theme: MarkdownTheme, selectFontSize: ((CGFloat) -> Void)? = nil) {
        self.source = source
        self.theme = theme
        self.selectFontSize = selectFontSize
    }

    public var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            item(String(localized: theme.appearance.label))
            divider
            fontSizeItem
            divider
            // 数は `.formatted()` せずに差し込む。`String(localized:)` が桁区切りを入れる
            // （2026-09-11 に実測。1234 → "1,234 行"）。数を書式指定子（%lld）のまま
            // 残しておくと、英語の "1 line" / "25 lines" をカタログの側で書き分けられる。
            item(String(localized: "\(DocumentSize.lineCount(of: source)) 行", bundle: .module))
            divider
            item(DocumentSize.byteLabel(of: source))
        }
        .font(.system(size: 11).monospacedDigit())
        .foregroundStyle(Color(platform: theme.quote))
        // **右だけ広く取る。** この帯は窓の右下の角にあり、角の丸みが余白を食う。
        // 左右とも 12pt にしていたときは、文字の右端から窓の縁まで 9.5pt しかなく、
        // 少し下の行では曲線が文字に寄っていた（実測）。
        //
        // 左は広げても見た目に出ない（右寄せなので左側には何も無い）。
        .padding(.leading, 12)
        .padding(.trailing, 40)
        .frame(height: 22)
        .background(alignment: .top) {
            // 本文と地続きに見せたうえで、細い線だけで区切る。
            Color(platform: theme.background)
                .overlay(alignment: .top) {
                    Color(platform: theme.marker).opacity(0.25).frame(height: 1)
                }
        }
        // 読み上げでは1つの情報のまとまりとして扱う。
        // 文字サイズを選べるときは、そのメニューに届くように中身を残す（`.combine` だと押せない）。
        .accessibilityElement(children: selectFontSize == nil ? .combine : .contain)
    }

    private func item(_ text: String) -> some View {
        Text(text).lineLimit(1)
    }

    private var fontSizeLabel: String { "\(Int(theme.fontSize)) pt" }

    /// 文字サイズ。押すと、設定画面のスライダーと同じ範囲を 1pt 刻みで並べたメニューが開く（#005）。
    ///
    /// **見た目はほかの項目と同じ文字のまま。** 印（▼）は付けず、指を乗せたときだけ
    /// 下地を薄く敷いて、押せることを知らせる。
    @ViewBuilder
    private var fontSizeItem: some View {
        #if os(macOS)
        if let selectFontSize {
            FontSizeMenu(label: fontSizeLabel, current: Int(theme.fontSize), select: selectFontSize)
        } else {
            item(fontSizeLabel)
        }
        #else
        item(fontSizeLabel)
        #endif
    }

    private var divider: some View {
        Text(verbatim: "·").padding(.horizontal, 8).opacity(0.6)
    }
}

#if os(macOS)
/// フッターの文字サイズのメニュー。
private struct FontSizeMenu: View {

    let label: String
    let current: Int
    let select: (CGFloat) -> Void

    @State private var isHovered = false

    private static let sizes = Int(MarkdownTheme.minimumFontSize)...Int(MarkdownTheme.maximumFontSize)

    var body: some View {
        Menu {
            ForEach(Self.sizes, id: \.self) { size in
                Toggle(isOn: Binding(get: { size == current }, set: { _ in select(CGFloat(size)) })) {
                    Text(verbatim: "\(size) pt")
                }
            }
            Divider()
            Button(String(localized: "文字サイズを戻す", bundle: .module)) {
                select(MarkdownTheme.defaultFontSize)
            }
        } label: {
            Text(label).lineLimit(1)
        }
        // 枠なしのメニュー（`.borderlessButton`）は、ラベルの文字の大きさと色を自前で決めてしまい、
        // ほかの項目より大きく、アクセントの色で出る（実測）。ラベルをそのまま描かせる。
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
        )
        // 下地のぶん左右に広げたので、ほかの項目との間隔が変わらないよう打ち消す。
        .padding(.horizontal, -4)
        .onHover { isHovered = $0 }
        .help(Text("文字サイズ", bundle: .module))
    }
}
#endif

/// 本文の大きさの数え方。
///
/// エディタの行番号と同じ数え方にすること。片方だけ「最後の空行」を
/// 数えたり数えなかったりすると、見比べたときに食い違う。
enum DocumentSize {

    /// 行数。末尾が改行なら、その後ろの空行も1行として数える
    /// （行番号の帯もそう数えている）。
    static func lineCount(of source: String) -> Int {
        var count = 1
        for character in source where character.isNewline {
            count += 1
        }
        return count
    }

    /// UTF-8 での大きさ。保存したときのファイルの大きさと一致する。
    static func byteLabel(of source: String) -> String {
        source.utf8.count.formatted(.byteCount(style: .file))
    }
}
