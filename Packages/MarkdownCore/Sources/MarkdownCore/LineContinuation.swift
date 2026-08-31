import Foundation

/// 改行したときに、行頭の印を継ぐかどうか。
public enum LineContinuation: Equatable {
    /// ふつうの改行。
    case plain
    /// 改行して、この文字列を続ける。インデントと引用の `>` を含む。
    case carry(String)
    /// 中身が空だった。行頭からこの文字数（UTF-16）を消して、改行だけ入れる。
    case end(clearing: Int)
}

/// 改行のときに何をするかを決める。
///
/// **副作用を持たない。** 判断だけをここに集めて、テストで縛る。
/// 実際に本文を書き換えるのは呼ぶ側（`FocusReportingTextView.insertNewline`）。
///
/// ## 継ぐもの
///
/// | 打っている行 | 次の行 |
/// |---|---|
/// | `- りんご` | `- ` |
/// | `3. さんばんめ` | `1. ` |
/// | `> 引用` | `> ` |
/// | `>> 入れ子の引用` | `>> ` |
/// | `> - りんご` | `> - ` |
/// | `  - 入れ子` | `  - ` |
///
/// ## 決めたこと（2026-08-31）
///
/// | | |
/// |---|---|
/// | 順序つきリストの番号 | **常に `1.`。** Markdown は 1 が並んでも 1,2,3 と描く。行を挿しても番号を直さなくてよい |
/// | 中身が空の行で改行 | **印を消して抜ける。** これが無いとリストや引用を終われない |
/// | タスクリスト | **`- ` だけ継ぐ。** `[ ]` は本文の側なので、特別扱いをしていない |
/// | 引用とリストが重なった `> - ` | **両方まとめて消す。** 段階的に抜ける形にすると、`> ` だけの行が残る |
///
/// リストの区切り文字（`.` と `)`、`-` と `*` と `+`）は**書かれたものをそのまま引き継ぐ**。
/// 番号だけを 1 に寄せる。人が選んだ書き方を勝手に変えない。
/// 引用の `>` だけは、後ろに空白が無くても**空白ひとつを補う**（`>引用` → `> `）。
/// ここは書き方の好みではなく、続きが読めるかどうかの問題。
public enum LineContinuationRule {

    /// - Parameters:
    ///   - line: いまカーソルがある行。**改行文字を含まない。**
    ///   - caretUTF16Offset: 行頭から数えたカーソルの位置。
    ///   - isInsideCode: コードブロックの中か。中なら何もしない。
    public static func decide(
        line: String, caretUTF16Offset caret: Int, isInsideCode: Bool = false
    ) -> LineContinuation {
        // コードブロックの中の `- foo` や `> foo` は記法ではない。ただの文字。
        guard !isInsideCode else { return .plain }

        var cursor = line.startIndex

        // インデント。空白でもタブでも、書かれたものをそのまま継ぐ。
        let indentStart = cursor
        while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
            cursor = line.index(after: cursor)
        }
        let indent = String(line[indentStart..<cursor])

        // 引用。`>` が続くだけ重ねる。`>> ` のような入れ子もそのまま。
        var quote = ""
        while cursor < line.endIndex, line[cursor] == ">" {
            quote += ">"
            cursor = line.index(after: cursor)
            var afterMarker = cursor
            var sawSpace = false
            while afterMarker < line.endIndex,
                  line[afterMarker] == " " || line[afterMarker] == "\t" {
                afterMarker = line.index(after: afterMarker)
                sawSpace = true
            }
            // `>` のあいだの空白は、**書かれたとおりに継ぐ。**
            // `>>` は `>>`、`> >` は `> >`。人が選んだ書き方を変えない。
            if sawSpace, afterMarker < line.endIndex, line[afterMarker] == ">" { quote += " " }
            cursor = afterMarker
        }
        if !quote.isEmpty { quote += " " }

        // リスト。引用の中にあってもよい（`> - りんご`）。
        var list = ""
        if let marker = BlockScanner.listMarker(line, cursor..<line.endIndex) {
            list = carriedListMarker(String(line[marker.markerRange])) + " "
            cursor = marker.contentRange.lowerBound
        }

        // 印がひとつも無い。ふつうの行。
        guard !quote.isEmpty || !list.isEmpty else { return .plain }

        // カーソルが印の中にある。`- ` の `-` と ` ` のあいだなど。
        // ここで継ぐと、印を割った残りに印が付く。触らない。
        let contentStart = utf16Offset(of: cursor, in: line)
        guard caret >= contentStart else { return .plain }

        // 中身が空。印だけの行で改行した。抜ける合図とみなす。
        // **行末にいるときだけ。** 途中にカーソルがあるなら、後ろに何か書いてある。
        if cursor == line.endIndex, caret == line.utf16.count {
            return .end(clearing: caret)
        }

        return .carry(indent + quote + list)
    }

    /// 次の行に置くリストの印。**番号だけを 1 に寄せ、区切り文字は引き継ぐ。**
    private static func carriedListMarker(_ marker: String) -> String {
        guard let last = marker.last, last == "." || last == ")" else {
            return marker  // `-` `*` `+` はそのまま
        }
        return "1\(last)"
    }

    private static func utf16Offset(of index: String.Index, in text: String) -> Int {
        text.utf16.distance(from: text.utf16.startIndex, to: index.samePosition(in: text.utf16)!)
    }
}
