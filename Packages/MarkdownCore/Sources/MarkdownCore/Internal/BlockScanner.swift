import Foundation

/// 行頭の記法（ブロック要素）を1行単位で認識する。
///
/// どの関数も「見つからなければ nil」を返すだけで、判定の優先順位は
/// `MarkdownTokenizer` 側が握る。
enum BlockScanner {

    // MARK: - 空白

    /// 行頭の空白を読み飛ばし、インデント幅（タブは4カラム換算）と本文開始位置を返す。
    static func measureIndent(_ text: String, _ range: Range<String.Index>) -> (width: Int, contentStart: String.Index) {
        var width = 0
        var index = range.lowerBound
        while index < range.upperBound {
            switch text[index] {
            case " ":
                width += 1
            case "\t":
                width += 4 - (width % 4)
            default:
                return (width, index)
            }
            index = text.index(after: index)
        }
        return (width, range.upperBound)
    }

    // MARK: - HTML コメント

    /// `<!--` で始まる行が、同じ行で閉じているか。
    enum HTMLCommentStart {
        /// 同じ行に `-->` があった。この行で終わり。
        case closedOnSameLine
        /// 閉じていない。次の行へ持ち越す。
        case staysOpen
    }

    /// この行が `<!--` で始まるなら、その閉じ方。始まらなければ `nil`。
    ///
    /// 字下げが4以上の行は呼ぶ側でコードブロックとして処理済みなので、ここでは見ない。
    static func htmlCommentOpen(_ text: String, _ range: Range<String.Index>) -> HTMLCommentStart? {
        guard text[range].hasPrefix("<!--") else { return nil }
        let afterOpening = text.index(range.lowerBound, offsetBy: 4, limitedBy: range.upperBound)
            ?? range.upperBound
        return htmlCommentClose(text, afterOpening..<range.upperBound) == nil
            ? .staysOpen : .closedOnSameLine
    }

    /// この行の中の `-->` の範囲。無ければ `nil`。
    static func htmlCommentClose(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        text.range(of: "-->", range: range)
    }

    /// **空行に見えるのに、空行にならない行**なら、その範囲。
    ///
    /// 中身がすべて空白でありながら、半角スペースとタブ以外の空白
    /// （全角スペース、ノーブレークスペースなど）を含む行がこれにあたる。
    /// CommonMark はこれを空行とみなさないので、段落が途切れない。
    ///
    /// 半角スペースとタブだけの行は**本当に空行になる**ので、対象にしない。
    static func invisibleBlankLine(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        guard range.lowerBound < range.upperBound else { return nil }
        var hasInvisible = false
        for character in text[range] {
            guard character.isWhitespace else { return nil }
            if character != " " && character != "\t" { hasInvisible = true }
        }
        return hasInvisible ? range : nil
    }

    /// 前後の空白を取り除いた範囲。
    static func trimmed(_ text: String, _ range: Range<String.Index>) -> Range<String.Index> {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, text[lower].isWhitespace {
            lower = text.index(after: lower)
        }
        while upper > lower, text[text.index(before: upper)].isWhitespace {
            upper = text.index(before: upper)
        }
        return lower..<upper
    }

    // MARK: - コードフェンス

    struct Fence {
        let marker: MarkdownBlockState.FenceMarker
        let length: Int
        let markerRange: Range<String.Index>
        /// 情報文字列（言語名）。無ければ空。
        let infoRange: Range<String.Index>
    }

    /// 開始フェンス ``` ``` ``` / `~~~` を検出する。
    static func openingFence(_ text: String, _ range: Range<String.Index>) -> Fence? {
        guard range.lowerBound < range.upperBound,
              let marker = MarkdownBlockState.FenceMarker(rawValue: text[range.lowerBound])
        else { return nil }

        var end = range.lowerBound
        while end < range.upperBound, text[end] == marker.rawValue {
            end = text.index(after: end)
        }
        guard text.distance(from: range.lowerBound, to: end) >= 3 else { return nil }

        let info = trimmed(text, end..<range.upperBound)
        // バッククォートのフェンスでは、情報文字列にバッククォートを含められない。
        if marker == .backtick, text[info].contains("`") { return nil }

        return Fence(
            marker: marker,
            length: text.distance(from: range.lowerBound, to: end),
            markerRange: range.lowerBound..<end,
            infoRange: info
        )
    }

    /// 閉じフェンスを検出する。同じ記号が `minimumLength` 個以上並び、他に文字が無いこと。
    static func closingFence(
        _ text: String,
        _ range: Range<String.Index>,
        marker: MarkdownBlockState.FenceMarker,
        minimumLength: Int
    ) -> Range<String.Index>? {
        let (indent, start) = measureIndent(text, range)
        guard indent <= 3, start < range.upperBound, text[start] == marker.rawValue else { return nil }

        var end = start
        while end < range.upperBound, text[end] == marker.rawValue {
            end = text.index(after: end)
        }
        guard text.distance(from: start, to: end) >= minimumLength else { return nil }
        guard text[end..<range.upperBound].allSatisfy(\.isWhitespace) else { return nil }
        return start..<end
    }

    // MARK: - 水平線

    /// `---` `***` `___`（間に空白が入ってもよい）。
    static func thematicBreak(_ text: String, _ range: Range<String.Index>) -> Range<String.Index>? {
        guard range.lowerBound < range.upperBound else { return nil }
        let symbol = text[range.lowerBound]
        guard symbol == "-" || symbol == "*" || symbol == "_" else { return nil }

        var count = 0
        for character in text[range] {
            if character == symbol {
                count += 1
            } else if character == " " || character == "\t" {
                continue
            } else {
                return nil
            }
        }
        guard count >= 3 else { return nil }
        return trimmed(text, range)
    }

    // MARK: - ATX 見出し

    struct ATXHeading {
        let level: Int
        let markerRange: Range<String.Index>
        /// 見出し本文。`# ` だけの行では空。
        let textRange: Range<String.Index>
        /// 末尾の閉じシーケンス `###`。無ければ nil。
        let closingRange: Range<String.Index>?
    }

    static func atxHeading(_ text: String, _ range: Range<String.Index>) -> ATXHeading? {
        var end = range.lowerBound
        while end < range.upperBound, text[end] == "#" {
            end = text.index(after: end)
        }
        let level = text.distance(from: range.lowerBound, to: end)
        guard (1...6).contains(level) else { return nil }
        // `#` の直後は空白か行末でなければならない（`#hashtag` は見出しではない）。
        guard end == range.upperBound || text[end] == " " || text[end] == "\t" else { return nil }

        var body = trimmed(text, end..<range.upperBound)
        var closing: Range<String.Index>?

        if !body.isEmpty {
            var closingStart = body.upperBound
            while closingStart > body.lowerBound, text[text.index(before: closingStart)] == "#" {
                closingStart = text.index(before: closingStart)
            }
            let isClosingSequence = closingStart < body.upperBound
                && (closingStart == body.lowerBound || text[text.index(before: closingStart)] == " ")
            if isClosingSequence {
                closing = closingStart..<body.upperBound
                body = trimmed(text, body.lowerBound..<closingStart)
            }
        }

        return ATXHeading(
            level: level,
            markerRange: range.lowerBound..<end,
            textRange: body,
            closingRange: closing
        )
    }

    // MARK: - リスト

    struct ListMarker {
        let markerRange: Range<String.Index>
        /// マーカーと続く空白を除いた本文。
        let contentRange: Range<String.Index>
    }

    static func listMarker(_ text: String, _ range: Range<String.Index>) -> ListMarker? {
        guard range.lowerBound < range.upperBound else { return nil }
        var index = range.lowerBound
        let first = text[index]

        if first == "-" || first == "*" || first == "+" {
            index = text.index(after: index)
        } else if first.isASCII, first.isNumber {
            var digits = 0
            while index < range.upperBound, text[index].isASCII, text[index].isNumber, digits < 9 {
                index = text.index(after: index)
                digits += 1
            }
            guard index < range.upperBound, text[index] == "." || text[index] == ")" else { return nil }
            index = text.index(after: index)
        } else {
            return nil
        }

        // マーカー直後は空白または行末。`*強調*` を誤検出しないための条件。
        guard index == range.upperBound || text[index] == " " || text[index] == "\t" else { return nil }

        var contentStart = index
        while contentStart < range.upperBound, text[contentStart] == " " || text[contentStart] == "\t" {
            contentStart = text.index(after: contentStart)
        }
        return ListMarker(markerRange: range.lowerBound..<index, contentRange: contentStart..<range.upperBound)
    }

    // MARK: - タスクリスト

    struct TaskMarker {
        /// `[ ]` `[x]` 全体。
        let range: Range<String.Index>
        let isChecked: Bool
        /// チェックボックスと続く空白を除いた本文。
        let contentRange: Range<String.Index>
    }

    /// リストマーカーの直後にあるチェックボックスを検出する。
    static func taskMarker(_ text: String, _ range: Range<String.Index>) -> TaskMarker? {
        var index = range.lowerBound
        guard index < range.upperBound, text[index] == "[" else { return nil }
        index = text.index(after: index)

        guard index < range.upperBound else { return nil }
        let isChecked: Bool
        switch text[index] {
        case " ": isChecked = false
        case "x", "X": isChecked = true
        default: return nil
        }
        index = text.index(after: index)

        guard index < range.upperBound, text[index] == "]" else { return nil }
        let markerEnd = text.index(after: index)
        // チェックボックスの直後は空白か行末。
        guard markerEnd == range.upperBound || text[markerEnd] == " " || text[markerEnd] == "\t" else { return nil }

        var contentStart = markerEnd
        while contentStart < range.upperBound, text[contentStart] == " " || text[contentStart] == "\t" {
            contentStart = text.index(after: contentStart)
        }
        return TaskMarker(
            range: range.lowerBound..<markerEnd,
            isChecked: isChecked,
            contentRange: contentStart..<range.upperBound
        )
    }
}
