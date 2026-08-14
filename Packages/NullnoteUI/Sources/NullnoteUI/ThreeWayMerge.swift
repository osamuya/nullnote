import Foundation

/// 3つの版を突き合わせて1つにまとめる。
///
/// 「最後に双方が一致していた内容（`base`）」を基準に、
/// 自分の直し（`ours`）と外の直し（`theirs`）を重ね合わせる。
/// **別の場所を直しているだけなら黙って合流し、同じ場所を直しているところにだけ印を入れる。**
/// git のマージと同じ考え方。
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

    private static func merge(
        base: [String], ours: [String], theirs: [String]
    ) -> (lines: [String], conflictCount: Int) {

        // 基準の各行が、双方のどの行に対応するか。対応が無ければ nil。
        let toOurs = alignment(from: base, to: ours)
        let toTheirs = alignment(from: base, to: theirs)

        var lines: [String] = []
        var conflicts = 0
        var (b, o, t) = (0, 0, 0)

        while b < base.count || o < ours.count || t < theirs.count {
            // 3つとも同じ位置で一致しているあいだは、そのまま流す。
            if b < base.count, toOurs[b] == o, toTheirs[b] == t {
                lines.append(base[b])
                b += 1; o += 1; t += 1
                continue
            }

            // 揃っていない区間。次に3つが揃う点まで、まとめて扱う。
            let stop = nextStable(from: b, ourIndex: o, theirIndex: t, toOurs: toOurs, toTheirs: toTheirs,
                                  base: base, ours: ours, theirs: theirs)
            let baseChunk = Array(base[b..<stop.base])
            let ourChunk = Array(ours[o..<stop.ours])
            let theirChunk = Array(theirs[t..<stop.theirs])

            if ourChunk == theirChunk {
                // 同じ直し方をしていた。どちらでもよい。
                lines += ourChunk
            } else if ourChunk == baseChunk {
                // 自分は触っていない。外の直しを採る。
                lines += theirChunk
            } else if theirChunk == baseChunk {
                // 外は触っていない。自分の直しを採る。
                lines += ourChunk
            } else {
                // 同じところを別々に直した。**ここだけ人に決めてもらう。**
                lines.append(ourMarker)
                lines += ourChunk
                lines.append(separator)
                lines += theirChunk
                lines.append(theirMarker)
                conflicts += 1
            }

            b = stop.base; o = stop.ours; t = stop.theirs
        }
        return (lines, conflicts)
    }

    /// 次に3つが揃う位置。無ければ、それぞれの終端。
    private static func nextStable(
        from base: Int, ourIndex: Int, theirIndex: Int,
        toOurs: [Int?], toTheirs: [Int?],
        base allBase: [String], ours: [String], theirs: [String]
    ) -> (base: Int, ours: Int, theirs: Int) {
        var index = base
        while index < allBase.count {
            if let o = toOurs[index], let t = toTheirs[index], o >= ourIndex, t >= theirIndex {
                return (index, o, t)
            }
            index += 1
        }
        return (allBase.count, ours.count, theirs.count)
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
