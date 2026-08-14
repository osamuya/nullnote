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

    public init(source: String, theme: MarkdownTheme) {
        self.source = source
        self.theme = theme
    }

    public var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            item(theme.appearance.label)
            divider
            item("\(Int(theme.fontSize)) pt")
            divider
            item("\(DocumentSize.lineCount(of: source).formatted()) 行")
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
        .accessibilityElement(children: .combine)
    }

    private func item(_ text: String) -> some View {
        Text(text).lineLimit(1)
    }

    private var divider: some View {
        Text("·").padding(.horizontal, 8).opacity(0.6)
    }
}

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
