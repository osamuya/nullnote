import Foundation

/// GFM の表を1行単位で認識する。
enum TableScanner {

    struct Row {
        /// 区切りの `|` の位置。
        let pipes: [Range<String.Index>]
        /// セルの内容（前後の空白を除いた範囲）。空セルもそのまま含む。
        let cells: [Range<String.Index>]
    }

    /// パイプで区切られた行として読む。エスケープされていない `|` が1つも無ければ nil。
    ///
    /// 行頭・行末の `|` は任意。あった場合、その外側にできる空セルは数えない。
    static func row(_ text: String, _ range: Range<String.Index>) -> Row? {
        let line = BlockScanner.trimmed(text, range)
        guard !line.isEmpty else { return nil }

        var pipes: [Range<String.Index>] = []
        var cells: [Range<String.Index>] = []
        var cellStart = line.lowerBound
        var index = line.lowerBound

        while index < line.upperBound {
            let character = text[index]
            if character == "\\" {
                index = text.index(after: index)
                if index < line.upperBound { index = text.index(after: index) }
                continue
            }
            if character == "|" {
                let next = text.index(after: index)
                pipes.append(index..<next)
                cells.append(BlockScanner.trimmed(text, cellStart..<index))
                cellStart = next
                index = next
                continue
            }
            index = text.index(after: index)
        }
        cells.append(BlockScanner.trimmed(text, cellStart..<line.upperBound))

        guard !pipes.isEmpty else { return nil }

        // 行頭・行末のパイプが作る空セルを落とす。
        if pipes.first?.lowerBound == line.lowerBound {
            cells.removeFirst()
        }
        if pipes.last?.upperBound == line.upperBound, !cells.isEmpty {
            cells.removeLast()
        }
        return Row(pipes: pipes, cells: cells)
    }

    /// 区切り行（`| --- | :-: |`）かどうか。
    static func isDelimiterRow(_ text: String, _ row: Row) -> Bool {
        !row.cells.isEmpty && row.cells.allSatisfy { isDelimiterCell(text, $0) }
    }

    /// 区切りセル: 任意の `:` + 1個以上の `-` + 任意の `:`。
    private static func isDelimiterCell(_ text: String, _ cell: Range<String.Index>) -> Bool {
        var index = cell.lowerBound
        if index < cell.upperBound, text[index] == ":" {
            index = text.index(after: index)
        }
        var dashes = 0
        while index < cell.upperBound, text[index] == "-" {
            dashes += 1
            index = text.index(after: index)
        }
        if index < cell.upperBound, text[index] == ":" {
            index = text.index(after: index)
        }
        return dashes >= 1 && index == cell.upperBound
    }
}
