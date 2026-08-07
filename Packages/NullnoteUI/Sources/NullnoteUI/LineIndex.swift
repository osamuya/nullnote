import Foundation

/// 文字位置と行番号を相互に引くための索引。
///
/// スクロール中に毎回文字列を走査すると、長い文書で無駄が大きい。
/// 本文が変わったときだけ作り直し、引くのは二分探索で済ませる。
struct LineIndex {

    /// 各行の先頭の UTF-16 オフセット。必ず 1 要素以上入る。
    private let starts: [Int]

    init(_ text: String) {
        var starts = [0]
        var offset = 0
        for character in text {
            offset += character.utf16.count
            if character.isNewline {
                starts.append(offset)
            }
        }
        // 末尾が改行だった場合、最後に空行の開始位置が入る。行数として数えてよい。
        self.starts = starts
    }

    /// 行数。
    var lineCount: Int { starts.count }

    /// その行の先頭の UTF-16 オフセット。行番号は 1 始まり。
    /// 範囲外の行番号は、いちばん近い行に丸める。
    func utf16Offset(ofLine line: Int) -> Int {
        starts[min(max(line - 1, 0), starts.count - 1)]
    }

    /// UTF-16 オフセットが何行目か。1 始まり。
    func line(atUTF16Offset offset: Int) -> Int {
        guard offset > 0 else { return 1 }

        var low = 0
        var high = starts.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if starts[middle] <= offset {
                low = middle
            } else {
                high = middle - 1
            }
        }
        return low + 1
    }
}
