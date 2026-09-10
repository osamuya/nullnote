import Foundation

/// 合流の印で割られたところ。行番号は **0 始まり**。
public struct ConflictRegion: Equatable, Sendable {

    /// `<<<<<<< 自分の更新` の行。
    public let ourMarkerLine: Int
    /// `=======` の行。
    public let separatorLine: Int
    /// `>>>>>>> 外部の更新` の行。
    public let theirMarkerLine: Int

    public init(ourMarkerLine: Int, separatorLine: Int, theirMarkerLine: Int) {
        self.ourMarkerLine = ourMarkerLine
        self.separatorLine = separatorLine
        self.theirMarkerLine = theirMarkerLine
    }

    /// 自分の版の中身。**印の行は含まない。**
    public var ourBody: Range<Int> { (ourMarkerLine + 1)..<separatorLine }
    /// 外の版の中身。**印の行は含まない。**
    public var theirBody: Range<Int> { (separatorLine + 1)..<theirMarkerLine }
    /// 印を含めた全体。
    public var all: Range<Int> { ourMarkerLine..<(theirMarkerLine + 1) }
}

/// 本文の中から、合流の印で割られたところを探す。
///
/// **`ThreeWayMerge` が書いた印だけを見る。** 綴りが一致する行だけを印として扱い、
/// git の一般形（`<<<<<<< branch-name` など）は拾わない。
/// 編集画面の色分け（`MarkdownTokenizer`）と同じ見方にしてある。
/// 片方だけ揃わない形は**印として扱わない**（本文として描く）。
///
/// 印は Markdown の記法ではないので、そのまま `Document(parsing:)` に渡すと
/// `=======` が下線見出しになり、`>>>>>>>` が7重の引用になる。
/// **周りの本文の意味まで変わる**ので、解釈させる前にここで切り分ける（D-60）。
public enum ConflictScanner {

    /// - Parameter lines: 本文を `\n` で切ったもの。
    public static func regions(in lines: [String]) -> [ConflictRegion] {
        var found: [ConflictRegion] = []
        var ourMarker: Int?
        var separator: Int?

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)

            if line == ThreeWayMerge.ourMarker {
                // 入れ子にはならない。開いたまま次の開きが来たら、新しい方を採る。
                ourMarker = index
                separator = nil
            } else if line == ThreeWayMerge.separator, ourMarker != nil, separator == nil {
                separator = index
            } else if line == ThreeWayMerge.theirMarker,
                let start = ourMarker, let middle = separator {
                found.append(
                    ConflictRegion(
                        ourMarkerLine: start, separatorLine: middle, theirMarkerLine: index
                    )
                )
                ourMarker = nil
                separator = nil
            }
        }
        // 閉じていないものは印として扱わない。中途半端に割ると、
        // 書きかけの `<<<<<<<` を打っただけで本文が消えたように見える。
        return found
    }

    /// 本文をそのまま渡すとき。
    public static func regions(in source: String) -> [ConflictRegion] {
        regions(in: source.components(separatedBy: "\n"))
    }
}
