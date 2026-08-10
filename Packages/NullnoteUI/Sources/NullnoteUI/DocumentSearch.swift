import Foundation

/// 本文の中から検索語に一致する範囲を探す。
///
/// 判定は **大文字小文字を無視した部分一致だけ**。正規表現も単語単位も持たない。
/// 設定を増やすほど「なぜ当たらないのか」を切り分ける手間が増えるので、
/// 必要になってから足す。
///
/// 範囲は `String.Index` ではなく UTF-16 の `NSRange` で返す。
/// 渡す先が `NSTextStorage` なので、ここで揃えておくと変換が要らない。
public enum DocumentSearch {

    /// 一致する範囲を、先頭から順に返す。**重なりは作らない。**
    ///
    /// `aa` で `aaa` を探すと 1 件（0..<2）。見つかった範囲の直後から続きを探すため。
    /// 重なりまで数えると、ヒット件数が直感と合わなくなる。
    public static func matches(of query: String, in source: String) -> [NSRange] {
        guard !query.isEmpty, !source.isEmpty else { return [] }

        let text = source as NSString
        var result: [NSRange] = []
        var start = 0

        while start < text.length {
            let remaining = NSRange(location: start, length: text.length - start)
            let found = text.range(of: query, options: [.caseInsensitive], range: remaining)
            guard found.location != NSNotFound else { break }
            result.append(found)
            // 長さ 0 の一致は起きない想定だが、起きたら進まず無限に回る。念のため 1 進める。
            start = found.location + max(found.length, 1)
        }
        return result
    }
}

/// エディタに重ねる検索のヒット。
///
/// 「どこを塗るか」だけを持つ。**スクロールはさせない。**
/// 打鍵のたびにヒットが数え直されるので、ここに移動の意味を持たせると
/// 本文を編集しているだけで画面が飛ぶ。移動は `EditorSelectionRequest` の側。
public struct SearchHighlight: Equatable, Sendable {

    /// ヒットした範囲。先頭から順に並ぶ。
    public let matches: [NSRange]
    /// いま見ているヒット。`matches` の添字。無いときは `nil`。
    public let current: Int?

    public init(matches: [NSRange], current: Int?) {
        self.matches = matches
        self.current = current
    }
}

/// 検索バーが持つ状態。検索語・ヒットの一覧・いま何番目か。
///
/// 画面から切り離してあるのは、前後への送りと件数の数え方をテストで縛るため。
/// 後から「同じ語をまとめて選ぶ」を作るときも、ヒットの求め方はここを使う。
public struct SearchSession: Equatable, Sendable {

    /// 検索語。画面の入力欄と直結する。
    public var query: String
    public private(set) var matches: [NSRange]
    /// `matches` の添字。ヒットが無いときは `nil`。
    public private(set) var currentIndex: Int?

    public init(query: String = "") {
        self.query = query
        self.matches = []
        self.currentIndex = nil
    }

    // MARK: - 数え直す

    /// 検索語か本文が変わったときに数え直す。
    ///
    /// いま見ていた位置は捨てない。**その位置以降の最初のヒット**を選び直すので、
    /// 語を1文字足したときに文書の先頭へ戻されない。
    public mutating func refresh(in source: String) {
        let anchor = currentRange?.location ?? 0
        matches = DocumentSearch.matches(of: query, in: source)
        currentIndex = matches.firstIndex { $0.location >= anchor } ?? (matches.isEmpty ? nil : matches.count - 1)
    }

    // MARK: - 送る

    /// 次のヒットへ。最後まで行ったら先頭へ戻る。
    public mutating func moveToNext() {
        guard let current = currentIndex else { return }
        currentIndex = (current + 1) % matches.count
    }

    /// 前のヒットへ。先頭より前へ行ったら末尾へ回る。
    public mutating func moveToPrevious() {
        guard let current = currentIndex else { return }
        currentIndex = (current - 1 + matches.count) % matches.count
    }

    // MARK: - 取り出す

    /// いま見ているヒットの範囲。
    public var currentRange: NSRange? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        return matches[currentIndex]
    }

    /// エディタへ渡す塗りの指示。
    public var highlight: SearchHighlight {
        SearchHighlight(matches: matches, current: currentIndex)
    }

    /// 入力欄の右に出す件数。
    ///
    /// 検索語が空のときは何も出さない。「0 件」と出すと、
    /// まだ何も打っていないのに見つからなかったように読める。
    public var countLabel: String {
        guard !query.isEmpty else { return "" }
        guard let currentIndex else { return "見つかりません" }
        return "\(currentIndex + 1) / \(matches.count)"
    }
}
