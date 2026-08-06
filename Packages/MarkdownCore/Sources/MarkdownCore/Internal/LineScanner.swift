import Foundation

/// 改行で区切られた1行分の範囲。
struct SourceLine: Hashable {
    /// 改行文字を含まない行本体。
    let content: Range<String.Index>
    /// 行末の改行文字。終端改行を持たない最終行では空。
    let terminator: Range<String.Index>
}

enum LineScanner {

    /// 文字列を行に分割する。
    ///
    /// `Character` は CRLF を1つの書記素として扱うため、`isNewline` で判定すれば
    /// LF / CR / CRLF / U+2028 などをまとめて正しく切れる。
    static func scan(_ text: String) -> [SourceLine] {
        var lines: [SourceLine] = []
        var lineStart = text.startIndex
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isNewline {
                let terminatorEnd = text.index(after: index)
                lines.append(SourceLine(content: lineStart..<index, terminator: index..<terminatorEnd))
                index = terminatorEnd
                lineStart = terminatorEnd
            } else {
                index = text.index(after: index)
            }
        }

        // 終端改行がない場合の最終行。空文字列も1行として扱う。
        if lineStart < text.endIndex || lines.isEmpty {
            lines.append(
                SourceLine(
                    content: lineStart..<text.endIndex,
                    terminator: text.endIndex..<text.endIndex
                )
            )
        }
        return lines
    }
}
