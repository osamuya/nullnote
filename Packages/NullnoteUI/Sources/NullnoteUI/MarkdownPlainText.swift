import Foundation
import MarkdownCore

/// トークンの範囲から、記法文字を取り除いた文字列を作る。
///
/// 目次（`DocumentOutline`）と、ファイル名の同期（`TitleSync`）が同じ答えを要る。
/// 別々に持つと、目次に出る見出しと、ファイル名になる見出しが食い違う。
enum MarkdownPlainText {

    /// 例: `# **設計** の [話](https://example.com)` の見出し範囲 → `設計 の 話`
    static func text(
        of range: Range<String.Index>,
        in source: String,
        tokens: [MarkdownToken]
    ) -> String {
        // 落とす範囲を集める。記法文字（`**` `[` `]` など）に加え、リンク先の URL も。
        let noise = tokens.filter { token in
            let isNoise: Bool
            switch token.kind {
            case .marker, .linkURL: isNoise = true
            default: isNoise = false
            }
            guard isNoise else { return false }
            return token.range.lowerBound >= range.lowerBound && token.range.upperBound <= range.upperBound
        }

        var result = ""
        var index = range.lowerBound
        for token in noise.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard token.range.lowerBound >= index else { continue }
            result += source[index..<token.range.lowerBound]
            index = token.range.upperBound
        }
        if index < range.upperBound {
            result += source[index..<range.upperBound]
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
}
