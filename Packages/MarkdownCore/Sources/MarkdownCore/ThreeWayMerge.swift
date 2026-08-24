import Foundation

/// 3つの版を突き合わせて1つにまとめる。
///
/// 「最後に双方が一致していた内容（`base`）」を基準に、
/// 自分の直し（`ours`）と外の直し（`theirs`）を重ね合わせる。
/// **別の場所を直しているだけなら黙って合流し、同じ場所を直しているところにだけ印を入れる。**
/// git のマージと同じ考え方。
///
/// ## 「同じ場所」の見方
///
/// 行の一致ではなく、**基準に対する編集の範囲が重なるか**で見る（diff3 と同じ）。
/// 隣り合う行を別々に直しても、範囲が接しているだけなら競合にしない。
/// 同じ行を別々に直したときと、同じ行に二人が書き足したときだけが競合になる
/// （後者は、どちらを先に置くか決めようが無いため）。理由は `docs/02-decision-log.md` の D-34。
///
/// ## 印の形
///
/// ```
/// <<<<<<< 自分の更新
/// 自分が書いた行
/// =======
/// 外で書かれた行
/// >>>>>>> 外部の更新
/// ```
///
/// **git と同じ形にしてある。** 見慣れているうえ、他のツールもこの形を競合として扱える。
///
/// ## 副作用を持たない
///
/// ファイルにも書類にも触らない。合流の判断だけをここに集めて、テストで縛る。
public enum ThreeWayMerge {

    public static let ourMarker = "<<<<<<< 自分の更新"
    public static let separator = "======="
    public static let theirMarker = ">>>>>>> 外部の更新"

    public struct Result: Equatable {
        /// 合流した結果。競合したところには印が入っている。
        public let text: String
        /// 印を入れた箇所の数。0 なら、そのまま使ってよい。
        public let conflictCount: Int

        public var hasConflicts: Bool { conflictCount > 0 }
    }

    public static func merge(base: String, ours: String, theirs: String) -> Result {
        // 行に切る。`components` は末尾の改行を空の行として残すので、
        // つなぎ直せば元に戻る（改行の有無が変わらない）。
        let merged = merge(
            base: base.components(separatedBy: "\n"),
            ours: ours.components(separatedBy: "\n"),
            theirs: theirs.components(separatedBy: "\n")
        )
        return Result(
            text: merged.lines.joined(separator: "\n"),
            conflictCount: merged.conflictCount
        )
    }

    // MARK: - 本体

    /// 基準の一部を、別の内容で置き換える指示。
    ///
    /// 片側の版を「基準に対する編集の並び」として表す。
    /// **重なりの判定を、行の一致ではなく編集の範囲どうしで行うため。**
    private struct Edit {
        /// 置き換える基準の範囲。空なら、その位置への挿入。
        let baseRange: Range<Int>
        let lines: [String]
    }

    private static func merge(
        base: [String], ours: [String], theirs: [String]
    ) -> (lines: [String], conflictCount: Int) {

        let ourEdits = edits(base: base, other: ours)
        let theirEdits = edits(base: base, other: theirs)

        var lines: [String] = []
        var conflicts = 0
        var index = 0      // 基準のどこまで出したか
        var o = 0, t = 0   // 使った編集の数

        while index < base.count || o < ourEdits.count || t < theirEdits.count {
            let ourStart = o < ourEdits.count ? ourEdits[o].baseRange.lowerBound : Int.max
            let theirStart = t < theirEdits.count ? theirEdits[t].baseRange.lowerBound : Int.max
            let next = min(ourStart, theirStart)

            // もう誰も触っていない。残りをそのまま流す。
            guard next != Int.max else {
                if index < base.count { lines += base[index...] }
                break
            }

            // 次の編集までは、3つとも同じ。
            if index < next {
                lines += base[index..<next]
                index = next
                continue
            }

            // ここから始まる編集の塊を取る。**重なっているあいだだけ**広げる。
            // 隣り合っているだけ（範囲が接しているだけ）なら、別の塊として扱う。
            var (upper, oEnd, tEnd) = (next, o, t)
            while true {
                var grew = false
                while oEnd < ourEdits.count, overlaps(ourEdits[oEnd], upper: upper, start: next) {
                    upper = max(upper, ourEdits[oEnd].baseRange.upperBound)
                    oEnd += 1
                    grew = true
                }
                while tEnd < theirEdits.count, overlaps(theirEdits[tEnd], upper: upper, start: next) {
                    upper = max(upper, theirEdits[tEnd].baseRange.upperBound)
                    tEnd += 1
                    grew = true
                }
                if !grew { break }
            }

            let range = next..<upper
            let ourChunk = apply(ourEdits[o..<oEnd], to: base, in: range)
            let theirChunk = apply(theirEdits[t..<tEnd], to: base, in: range)

            if oEnd == o {
                // 自分は触っていない。外の直しを採る。
                lines += theirChunk
            } else if tEnd == t {
                // 外は触っていない。自分の直しを採る。
                lines += ourChunk
            } else if ourChunk == theirChunk {
                // 同じ直し方をしていた。どちらでもよい。
                lines += ourChunk
            } else if supersedes(theirChunk, over: ourChunk, base: Array(base[range])) {
                // 相手はこちらの直しを取り込んだ上で、さらに書いている。
                lines += theirChunk
            } else if supersedes(ourChunk, over: theirChunk, base: Array(base[range])) {
                lines += ourChunk
            } else {
                // 重なるところを別々に直した。**ここだけ人に決めてもらう。**
                //
                // 印は**できるだけ小さく**する。両側で一致している行まで囲むと、
                // 同じ行が上下に並んで、どこが食い違っているのか読めない。
                let trimmed = trim(ours: ourChunk, theirs: theirChunk)
                lines += trimmed.prefix
                lines.append(ourMarker)
                lines += trimmed.ours
                lines.append(separator)
                lines += trimmed.theirs
                lines.append(theirMarker)
                lines += trimmed.suffix
                conflicts += 1
            }

            index = upper
            o = oEnd
            t = tEnd
        }
        return (lines, conflicts)
    }

    /// 印で囲む範囲を、食い違っているところだけに詰める。
    ///
    /// 前後で一致している行は、双方が同意している内容。印の外に出す。
    private static func trim(
        ours: [String], theirs: [String]
    ) -> (prefix: [String], ours: [String], theirs: [String], suffix: [String]) {
        var head = 0
        while head < ours.count, head < theirs.count, ours[head] == theirs[head] {
            head += 1
        }
        var tail = 0
        while head + tail < ours.count, head + tail < theirs.count,
              ours[ours.count - 1 - tail] == theirs[theirs.count - 1 - tail] {
            tail += 1
        }
        return (
            prefix: Array(ours[0..<head]),
            ours: Array(ours[head..<(ours.count - tail)]),
            theirs: Array(theirs[head..<(theirs.count - tail)]),
            suffix: Array(ours[(ours.count - tail)...])
        )
    }

    /// `winner` が `loser` の直しを、すでに取り込んでいるか。
    ///
    /// **外から書く道具が、こちらの保存を読んでから書いた場合**に効く。
    /// 相手の版にはこちらの直しがそのまま入っているので、印を出す理由が無い。
    /// これが無いと、隣り合う場所を触るたびに印が出て使い物にならない（D-35）。
    ///
    /// 見るのは足した行と消した行の集合。**位置は見ない。**
    /// 位置まで揃えようとすると、行を動かしただけで印が出る。
    ///
    /// **消すだけの直しは対象にしない。** 消したいという意図は相手の版には残らず、
    /// 「片方が消した行を、もう片方が直した」は人に決めてもらうべき場面。
    private static func supersedes(_ winner: [String], over loser: [String], base: [String]) -> Bool {
        let loserChange = change(from: base, to: loser)
        guard !loserChange.added.isEmpty else { return false }

        let winnerChange = change(from: base, to: winner)
        return loserChange.added.allSatisfy { winnerChange.added.contains($0) }
            && loserChange.removed.allSatisfy { winnerChange.removed.contains($0) }
    }

    /// 基準に対して、足された行と消された行。同じ行が何度も出る場合も数える。
    private static func change(
        from base: [String], to other: [String]
    ) -> (added: [String], removed: [String]) {
        var remaining = base
        var added: [String] = []
        for line in other {
            if let index = remaining.firstIndex(of: line) {
                remaining.remove(at: index)
            } else {
                added.append(line)
            }
        }
        return (added, remaining)
    }

    /// その編集を、いま作っている塊に取り込むか。
    ///
    /// 取り込むのは**範囲が重なっているとき**だけ。ただし塊の作り始め
    /// （`upper` がまだ開始位置のまま）は、同じ位置から始まるものを入れる。
    /// 挿入は範囲が空なので、これが無いと永久に取り込めない。
    private static func overlaps(_ edit: Edit, upper: Int, start: Int) -> Bool {
        let lower = edit.baseRange.lowerBound
        return lower < upper || (lower == upper && upper == start)
    }

    /// 片側の編集を基準に当てて、その範囲の「その側の版」を作る。
    private static func apply(
        _ edits: ArraySlice<Edit>, to base: [String], in range: Range<Int>
    ) -> [String] {
        var result: [String] = []
        var index = range.lowerBound
        for edit in edits {
            if index < edit.baseRange.lowerBound {
                result += base[index..<edit.baseRange.lowerBound]
            }
            result += edit.lines
            index = max(index, edit.baseRange.upperBound)
        }
        if index < range.upperBound { result += base[index..<range.upperBound] }
        return result
    }

    /// 片側の版を「基準に対する編集の並び」に直す。
    ///
    /// **ここで作る範囲が、重なりの判定の単位になる。**
    /// 対応の取れた行で区切るので、離れた直しは別々の編集になり、
    /// 隣り合う行を別々に直しても、互いに重ならないかぎり競合しない。
    private static func edits(base: [String], other: [String]) -> [Edit] {
        let matched = alignment(from: base, to: other)
        var result: [Edit] = []
        var (i, j) = (0, 0)

        while i < base.count {
            if let position = matched[i], position == j {
                i += 1; j += 1
                continue
            }
            // 次に対応が取れる基準の行まで、まとめて1つの編集にする。
            var stop = i
            while stop < base.count, matched[stop] == nil || matched[stop]! < j {
                stop += 1
            }
            let otherEnd = stop < base.count ? matched[stop]! : other.count
            result.append(Edit(baseRange: i..<stop, lines: Array(other[j..<otherEnd])))
            i = stop
            j = otherEnd
        }

        // 末尾に足された分。
        if j < other.count {
            result.append(Edit(baseRange: base.count..<base.count, lines: Array(other[j...])))
        }
        return result
    }

    // MARK: - 対応付け

    /// 基準の行が、相手のどの行に当たるか。
    ///
    /// 長さの揃わない差分を素直に解くと、行数の積だけ計算量と記憶域が要る。
    /// **先頭と末尾の一致は先に落とす。** 実際の編集は数行しか違わないので、
    /// これだけで対象がほぼ無くなる。
    private static func alignment(from base: [String], to other: [String]) -> [Int?] {
        var result = [Int?](repeating: nil, count: base.count)

        var head = 0
        while head < base.count, head < other.count, base[head] == other[head] {
            result[head] = head
            head += 1
        }

        var tail = 0
        while head + tail < base.count, head + tail < other.count,
              base[base.count - 1 - tail] == other[other.count - 1 - tail] {
            result[base.count - 1 - tail] = other.count - 1 - tail
            tail += 1
        }

        let baseMiddle = Array(base[head..<(base.count - tail)])
        let otherMiddle = Array(other[head..<(other.count - tail)])
        for (baseOffset, otherOffset) in longestCommonSubsequence(baseMiddle, otherMiddle) {
            result[head + baseOffset] = head + otherOffset
        }
        return result
    }

    /// 共通して現れる行の対応。動的計画法。
    ///
    /// 先頭と末尾を落としたあとに呼ぶので、ふつうの編集では数行しか残らない。
    /// それでも文書を丸ごと書き換えられた場合に備えて、大きすぎるときは諦める
    /// （対応なし＝全体が1つの競合になる。**間違った合流をするよりよい**）。
    private static func longestCommonSubsequence(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        guard a.count * b.count <= 4_000_000 else { return [] }

        var table = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] = a[i] == b[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var pairs: [(Int, Int)] = []
        var (i, j) = (0, 0)
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
