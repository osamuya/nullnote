import Foundation

/// 改行したときに、行頭の印を継ぐかどうか。
public enum LineContinuation: Equatable {
    /// ふつうの改行。
    case plain
    /// 改行して、この文字列を続ける。インデントと引用の `>` を含む。
    case carry(String)
    /// 中身が空だった。行頭からこの文字数（UTF-16）を消して、改行だけ入れる。
    case end(clearing: Int)
    /// コードフェンスを開いた。改行し、**空行を1つ挟んで**閉じフェンスを置く。
    /// カーソルはその空行に残す。
    case openFence(closing: String)
    /// 表の行。改行して `lines` を順に置き、**最初のセルにカーソルを置く**。
    ///
    /// 見出し行なら区切り行と空の行の2つ、本体なら空の行1つが入る。
    case tableRow(lines: [String], caretInFirstCellOf: Int)
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
    ///   - hasClosingFenceAhead: この行より後ろに、閉じになりうるフェンス行があるか。
    ///     **あるなら閉じを足さない。** CommonMark では、開いたフェンスの後ろに
    ///     現れる最初のフェンス行がそれを閉じる。二重に置くと、そちらが宙に浮く。
    ///   - blockState: この行を打ち始める前のブロック状態。表の中かどうかの判断に使う。
    public static func decide(
        line: String, caretUTF16Offset caret: Int, isInsideCode: Bool = false,
        hasClosingFenceAhead: Bool = false, blockState: MarkdownBlockState = .blank
    ) -> LineContinuation {
        // コードブロックの中の `- foo` や `> foo` は記法ではない。ただの文字。
        // フェンス行そのものも、中にいるなら「閉じ」なので何もしない。
        guard !isInsideCode else { return .plain }

        // 表の行。見出しなら区切りごと、本体なら空の行を足す。
        // **行末にいるときだけ。** 途中ならセルを打っている最中。
        if caret == line.utf16.count, let table = tableContinuation(line: line, state: blockState) {
            return table
        }

        // コードフェンスを開いた行。閉じを足して、あいだにカーソルを置く。
        // **行末にいるときだけ。** 途中なら言語名を打っている最中かもしれない。
        if caret == line.utf16.count, !hasClosingFenceAhead,
           let fence = BlockScanner.openingFence(line, trimmedIndent(of: line)) {
            return .openFence(closing: String(repeating: fence.marker.rawValue, count: fence.length))
        }

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

    /// 表の行での改行。見出しか本体かで、置くものが変わる。
    ///
    /// **見出しかどうかは状態では決まらない。** トークナイザが見出しと認めるのは
    /// 「次の行が列数の合う区切り行」のときだけなので、区切り行を書く前は
    /// ただの段落に見える。だから**表の中でなければ見出しとみなす**。
    private static func tableContinuation(
        line: String, state: MarkdownBlockState
    ) -> LineContinuation? {
        guard let row = TableScanner.row(line, line.startIndex..<line.endIndex) else { return nil }
        let columns = row.cells.count
        guard columns > 0 else { return nil }

        switch state {
        case .tableBody:
            // 中身が空の行なら、表から抜ける。
            if row.cells.allSatisfy({ line[$0].isEmpty }) { return .end(clearing: line.utf16.count) }
            return .tableRow(lines: [emptyRow(columns)], caretInFirstCellOf: 0)

        case .tableDelimiterExpected:
            // 区切り行の上でも、次は本体の行。
            return .tableRow(lines: [emptyRow(columns)], caretInFirstCellOf: 0)

        case .blank, .paragraph:
            // 見出し行。区切り行と、最初の本体の行を置く。
            return .tableRow(
                lines: [delimiterRow(columns), emptyRow(columns)], caretInFirstCellOf: 1
            )

        default:
            return nil
        }
    }

    /// `|---|---|`。この文書で圧倒的に多い書き方に合わせている。
    private static func delimiterRow(_ columns: Int) -> String {
        "|" + String(repeating: "---|", count: columns)
    }

    /// `|  |  |`。セルの中に空白を1つずつ置く。カーソルはその空白の上に来る。
    private static func emptyRow(_ columns: Int) -> String {
        "|" + String(repeating: "  |", count: columns)
    }

    /// 行頭の空白を除いた範囲。フェンスの判定に渡す。
    private static func trimmedIndent(of line: String) -> Range<String.Index> {
        var start = line.startIndex
        while start < line.endIndex, line[start] == " " || line[start] == "\t" {
            start = line.index(after: start)
        }
        return start..<line.endIndex
    }

    /// この行が、指定した記号・長さのフェンスを**閉じる**行か。
    ///
    /// **閉じフェンスに言語名は書けない**（CommonMark）。
    /// したがって後ろにある ```` ```swift ```` は閉じにならない。
    /// 「``` で始まる行」で数えると足すべき場面で足さなくなる（実測。B-21）。
    public static func closesFence(_ line: String, marker: Character, minimumLength: Int) -> Bool {
        guard let fenceMarker = MarkdownBlockState.FenceMarker(rawValue: marker) else { return false }
        return BlockScanner.closingFence(
            line, line.startIndex..<line.endIndex,
            marker: fenceMarker, minimumLength: minimumLength
        ) != nil
    }

    /// その行が開始フェンスなら、記号と長さを返す。後ろに閉じがあるかを調べる側で使う。
    public static func openingFenceShape(of line: String) -> (marker: Character, length: Int)? {
        guard let fence = BlockScanner.openingFence(line, trimmedIndent(of: line)) else { return nil }
        return (fence.marker.rawValue, fence.length)
    }

    private static func utf16Offset(of index: String.Index, in text: String) -> Int {
        text.utf16.distance(from: text.utf16.startIndex, to: index.samePosition(in: text.utf16)!)
    }
}
