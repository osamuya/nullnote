import Foundation

/// 編集画面で印を描く空白（#015・D-80）。
///
/// 半角と全角の空白は、どちらも画面では何も見えず、見分けがつかない。
/// - 半角スペースは `␣`。行末に2つ並ぶと Markdown の改行の印になる（D-79 で自動で入れる）
/// - 全角スペースは四角。段落の頭の字下げなどに使う
///
/// **本文には何も入れない。** 描くだけなので、コピー・保存・カーソルの動きは変わらない。
enum WhitespaceMark: Equatable {
    /// 半角スペース（U+0020）。`␣` の形で描く。
    case space
    /// 全角スペース（U+3000）。四角で描く。
    case ideographicSpace
}

enum WhitespaceMarks {

    /// 範囲の中で印を描く文字の位置（UTF-16）と種類。
    static func find(in text: NSString, range: NSRange) -> [(location: Int, mark: WhitespaceMark)] {
        var found: [(location: Int, mark: WhitespaceMark)] = []
        let end = min(NSMaxRange(range), text.length)
        guard range.location < end else { return found }
        for index in range.location..<end {
            switch text.character(at: index) {
            case 0x20: found.append((index, .space))
            case 0x3000: found.append((index, .ideographicSpace))
            default: continue
            }
        }
        return found
    }
}
