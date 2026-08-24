import Foundation

/// 1行の中の記法（インライン要素）を認識する。
///
/// CommonMark の delimiter-run アルゴリズム全体は実装していない。
/// エディタのハイライトに必要な範囲で、行をまたがない素直な対応付けを行う。
/// 未対応の挙動は `README.md` の「既知の制限」に列挙してある。
enum InlineScanner {

    /// `<!--` から始まる HTML コメント。
    ///
    /// 同じ行に `-->` があればそこまで。無ければ**行末まで**を返し、
    /// `isOpen` で「まだ閉じていない」ことを伝える。次の行へ持ち越すのは呼ぶ側の仕事。
    static func htmlComment(
        _ text: String, at index: String.Index, limit: String.Index
    ) -> (range: Range<String.Index>, isOpen: Bool)? {
        guard text[index..<limit].hasPrefix("<!--") else { return nil }
        let afterOpening = text.index(index, offsetBy: 4, limitedBy: limit) ?? limit
        guard let closing = text.range(of: "-->", range: afterOpening..<limit) else {
            return (index..<limit, true)
        }
        return (index..<closing.upperBound, false)
    }

    /// リンクや強調の入れ子をたどる深さの上限。
    /// 壊れた入力（`[[[[[...`）で再帰が深くなるのを防ぐ。
    static let maximumNestingDepth = 8

    /// - Returns: 行末の時点で **HTML コメントが開いたまま**なら `true`。
    ///   コメントだけは行をまたぐので、呼ぶ側がブロック状態に持ち越す。
    @discardableResult
    static func appendTokens(
        _ text: String,
        _ range: Range<String.Index>,
        depth: Int = 0,
        into tokens: inout [MarkdownToken]
    ) -> Bool {
        guard depth < maximumNestingDepth else { return false }

        var index = range.lowerBound
        while index < range.upperBound {
            switch text[index] {
            case "\\":
                if let next = appendEscape(text, at: index, limit: range.upperBound, into: &tokens) {
                    index = next
                    continue
                }
            case "`":
                if let next = appendCodeSpan(text, at: index, limit: range.upperBound, into: &tokens) {
                    index = next
                    continue
                }
            case "<":
                // コメントを先に見る。`<!--` はオートリンクにはなり得ない。
                if let comment = htmlComment(text, at: index, limit: range.upperBound) {
                    tokens.append(MarkdownToken(kind: .htmlComment, range: comment.range))
                    if comment.isOpen { return true }
                    index = comment.range.upperBound
                    continue
                }
                if let next = appendAutolink(text, at: index, limit: range.upperBound, into: &tokens) {
                    index = next
                    continue
                }
            case "[", "!":
                if let next = appendLink(text, at: index, limit: range.upperBound, depth: depth, into: &tokens) {
                    index = next
                    continue
                }
            case "*", "_":
                if let next = appendEmphasis(
                    text, at: index, limit: range.upperBound,
                    lineStart: range.lowerBound, depth: depth, into: &tokens
                ) {
                    index = next
                    continue
                }
            case "~":
                if let next = appendStrikethrough(
                    text, at: index, limit: range.upperBound, depth: depth, into: &tokens
                ) {
                    index = next
                    continue
                }
            case "@":
                if let span = emailAutolink(
                    text, at: index, rangeStart: range.lowerBound, limit: range.upperBound
                ) {
                    tokens.append(MarkdownToken(kind: .autolink, range: span))
                    index = span.upperBound
                    continue
                }
            case "h", "H", "w", "W":
                if let span = urlAutolink(
                    text, at: index, rangeStart: range.lowerBound, limit: range.upperBound
                ) {
                    tokens.append(MarkdownToken(kind: .autolink, range: span))
                    index = span.upperBound
                    continue
                }
            default:
                break
            }
            index = text.index(after: index)
        }
        return false
    }

    // MARK: - エスケープ

    private static func appendEscape(
        _ text: String,
        at start: String.Index,
        limit: String.Index,
        into tokens: inout [MarkdownToken]
    ) -> String.Index? {
        let escaped = text.index(after: start)
        guard escaped < limit, isASCIIPunctuation(text[escaped]) else { return nil }
        let end = text.index(after: escaped)
        tokens.append(MarkdownToken(kind: .marker(.escape), range: start..<escaped))
        tokens.append(MarkdownToken(kind: .escapedCharacter, range: escaped..<end))
        return end
    }

    private static func isASCIIPunctuation(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return false }
        return (0x21...0x2F).contains(ascii)
            || (0x3A...0x40).contains(ascii)
            || (0x5B...0x60).contains(ascii)
            || (0x7B...0x7E).contains(ascii)
    }

    // MARK: - インラインコード

    /// バッククォートの連続数が一致する箇所までを1つのコードスパンとする。
    private static func appendCodeSpan(
        _ text: String,
        at start: String.Index,
        limit: String.Index,
        into tokens: inout [MarkdownToken]
    ) -> String.Index? {
        guard let span = codeSpan(text, at: start, limit: limit) else { return nil }
        tokens.append(MarkdownToken(kind: .marker(.inlineCode), range: start..<span.contentStart))
        if span.contentStart < span.contentEnd {
            tokens.append(MarkdownToken(kind: .inlineCode, range: span.contentStart..<span.contentEnd))
        }
        tokens.append(MarkdownToken(kind: .marker(.inlineCode), range: span.contentEnd..<span.end))
        return span.end
    }

    private static func codeSpan(
        _ text: String,
        at start: String.Index,
        limit: String.Index
    ) -> (contentStart: String.Index, contentEnd: String.Index, end: String.Index)? {
        let contentStart = endOfRun(text, from: start, of: "`", limit: limit)
        let openLength = text.distance(from: start, to: contentStart)

        var index = contentStart
        while index < limit {
            guard text[index] == "`" else {
                index = text.index(after: index)
                continue
            }
            let runEnd = endOfRun(text, from: index, of: "`", limit: limit)
            if text.distance(from: index, to: runEnd) == openLength {
                return (contentStart, index, runEnd)
            }
            index = runEnd
        }
        return nil
    }

    // MARK: - オートリンク

    private static func appendAutolink(
        _ text: String,
        at start: String.Index,
        limit: String.Index,
        into tokens: inout [MarkdownToken]
    ) -> String.Index? {
        var index = text.index(after: start)
        var looksLikeURI = false

        while index < limit {
            let character = text[index]
            if character == ">" { break }
            // 空白や `<` を含むものは山括弧の対では扱わない。
            if character.isWhitespace || character == "<" { return nil }
            if character == ":" || character == "@" { looksLikeURI = true }
            index = text.index(after: index)
        }

        guard index < limit, text[index] == ">", looksLikeURI else { return nil }
        let contentStart = text.index(after: start)
        guard contentStart < index else { return nil }
        let end = text.index(after: index)

        tokens.append(MarkdownToken(kind: .marker(.autolinkAngle), range: start..<contentStart))
        tokens.append(MarkdownToken(kind: .autolink, range: contentStart..<index))
        tokens.append(MarkdownToken(kind: .marker(.autolinkAngle), range: index..<end))
        return end
    }

    // MARK: - リンク・画像

    private static func appendLink(
        _ text: String,
        at start: String.Index,
        limit: String.Index,
        depth: Int,
        into tokens: inout [MarkdownToken]
    ) -> String.Index? {
        // `![` の場合は `!` もマーカーに含める。
        var bracket = start
        if text[bracket] == "!" {
            bracket = text.index(after: bracket)
        }
        guard bracket < limit, text[bracket] == "[" else { return nil }

        guard let closeBracket = matchingDelimiter(text, from: bracket, open: "[", close: "]", limit: limit) else {
            return nil
        }
        let parenOpen = text.index(after: closeBracket)
        guard parenOpen < limit, text[parenOpen] == "(" else { return nil }
        guard let parenClose = matchingDelimiter(text, from: parenOpen, open: "(", close: ")", limit: limit) else {
            return nil
        }

        let textStart = text.index(after: bracket)
        let urlStart = text.index(after: parenOpen)
        let end = text.index(after: parenClose)

        tokens.append(MarkdownToken(kind: .marker(.linkBracket), range: start..<textStart))
        if textStart < closeBracket {
            tokens.append(MarkdownToken(kind: .linkText, range: textStart..<closeBracket))
        }
        tokens.append(MarkdownToken(kind: .marker(.linkBracket), range: closeBracket..<parenOpen))
        tokens.append(MarkdownToken(kind: .marker(.linkParen), range: parenOpen..<urlStart))
        if urlStart < parenClose {
            tokens.append(MarkdownToken(kind: .linkURL, range: urlStart..<parenClose))
        }
        tokens.append(MarkdownToken(kind: .marker(.linkParen), range: parenClose..<end))

        // 表示テキストの中の記法は外枠のあとに続けて並べる（外側 → 内側の順）。
        appendTokens(text, textStart..<closeBracket, depth: depth + 1, into: &tokens)
        return end
    }

    /// `from` にある開き記号に対応する閉じ記号を探す。入れ子とエスケープを考慮する。
    private static func matchingDelimiter(
        _ text: String,
        from start: String.Index,
        open: Character,
        close: Character,
        limit: String.Index
    ) -> String.Index? {
        var depth = 0
        var index = start
        while index < limit {
            let character = text[index]
            if character == "\\" {
                index = text.index(after: index)
                if index < limit { index = text.index(after: index) }
                continue
            }
            if character == open {
                depth += 1
            } else if character == close {
                depth -= 1
                if depth == 0 { return index }
            }
            index = text.index(after: index)
        }
        return nil
    }

    // MARK: - 強調

    private static func appendEmphasis(
        _ text: String,
        at start: String.Index,
        limit: String.Index,
        lineStart: String.Index,
        depth: Int,
        into tokens: inout [MarkdownToken]
    ) -> String.Index? {
        let symbol = text[start]
        let runEnd = endOfRun(text, from: start, of: symbol, limit: limit)
        let delimiterLength = min(text.distance(from: start, to: runEnd), 3)
        let contentStart = text.index(start, offsetBy: delimiterLength)

        // 開き側の条件: 直後が空白や行末でない。
        guard contentStart < limit, !text[contentStart].isWhitespace else { return nil }
        // `_` は単語の途中では強調を開始しない（snake_case を壊さない）。
        if symbol == "_", start > lineStart, isWordCharacter(text[text.index(before: start)]) {
            return nil
        }

        guard let closeRunEnd = closingDelimiter(
            text, symbol: symbol, length: delimiterLength,
            searchFrom: contentStart, limit: limit
        ) else { return nil }

        // 閉じ側の区切りは「連続の末尾から」使う。こうすると `**強調 *と斜体***` のように
        // 閉じ記号がまとまっている場合に、外側が最後の記号で閉じ、内側が残りで閉じる。
        let contentEnd = text.index(closeRunEnd, offsetBy: -delimiterLength)
        let end = closeRunEnd
        guard contentStart < contentEnd else { return nil }

        let marker: MarkdownToken.Marker = delimiterLength == 1 ? .emphasis : .strong
        tokens.append(MarkdownToken(kind: .marker(marker), range: start..<contentStart))
        if delimiterLength >= 2 {
            tokens.append(MarkdownToken(kind: .strong, range: contentStart..<contentEnd))
        }
        if delimiterLength != 2 {
            tokens.append(MarkdownToken(kind: .emphasis, range: contentStart..<contentEnd))
        }
        tokens.append(MarkdownToken(kind: .marker(marker), range: contentEnd..<end))

        appendTokens(text, contentStart..<contentEnd, depth: depth + 1, into: &tokens)
        return end
    }

    /// 閉じ側になれる区切りの連続を探し、その **末尾** の位置を返す。
    private static func closingDelimiter(
        _ text: String,
        symbol: Character,
        length: Int,
        searchFrom: String.Index,
        limit: String.Index
    ) -> String.Index? {
        var index = searchFrom
        while index < limit {
            let character = text[index]

            if character == "\\" {
                index = text.index(after: index)
                if index < limit { index = text.index(after: index) }
                continue
            }
            // インラインコードが優先されるため、その中の記号は閉じ側にならない。
            if character == "`", let span = codeSpan(text, at: index, limit: limit) {
                index = span.end
                continue
            }
            guard character == symbol else {
                index = text.index(after: index)
                continue
            }

            let runEnd = endOfRun(text, from: index, of: symbol, limit: limit)
            guard text.distance(from: index, to: runEnd) >= length, index > searchFrom else {
                index = runEnd
                continue
            }
            // 閉じ側の条件: 直前が空白でない。
            if text[text.index(before: index)].isWhitespace {
                index = runEnd
                continue
            }
            // `_` は単語の途中では強調を終了しない。
            if symbol == "_", runEnd < limit, isWordCharacter(text[runEnd]) {
                index = runEnd
                continue
            }
            return runEnd
        }
        return nil
    }

    // MARK: - 取り消し線（GFM）

    private static func appendStrikethrough(
        _ text: String,
        at start: String.Index,
        limit: String.Index,
        depth: Int,
        into tokens: inout [MarkdownToken]
    ) -> String.Index? {
        let contentStart = endOfRun(text, from: start, of: "~", limit: limit)
        let delimiterLength = text.distance(from: start, to: contentStart)
        // `~~~` 以上はコードフェンスの記号なので、取り消し線にはしない。
        // 連続の内側から数え直さないよう、ここでは連続全体を読み飛ばす。
        guard delimiterLength <= 2 else { return contentStart }
        guard contentStart < limit, !text[contentStart].isWhitespace else { return nil }

        guard let closeRunEnd = closingDelimiter(
            text, symbol: "~", length: delimiterLength,
            searchFrom: contentStart, limit: limit
        ) else { return nil }

        let contentEnd = text.index(closeRunEnd, offsetBy: -delimiterLength)
        guard contentStart < contentEnd else { return nil }

        tokens.append(MarkdownToken(kind: .marker(.strikethrough), range: start..<contentStart))
        tokens.append(MarkdownToken(kind: .strikethrough, range: contentStart..<contentEnd))
        tokens.append(MarkdownToken(kind: .marker(.strikethrough), range: contentEnd..<closeRunEnd))

        appendTokens(text, contentStart..<contentEnd, depth: depth + 1, into: &tokens)
        return closeRunEnd
    }

    // MARK: - 拡張オートリンク（GFM）

    /// 山括弧の無い裸の URL。`http://` `https://` `www.` で始まるものを拾う。
    private static func urlAutolink(
        _ text: String,
        at start: String.Index,
        rangeStart: String.Index,
        limit: String.Index
    ) -> Range<String.Index>? {
        guard isAutolinkBoundary(text, before: start, rangeStart: rangeStart) else { return nil }
        guard let prefix = ["https://", "http://", "www."].first(where: {
            hasPrefix($0, in: text, at: start, limit: limit)
        }) else { return nil }

        var end = start
        while end < limit, !text[end].isWhitespace, text[end] != "<" {
            end = text.index(after: end)
        }

        // 文末の句読点は URL に含めない。
        let trailingPunctuation: Set<Character> = ["?", "!", ".", ",", ":", ";", "*", "_", "~", "'", "\""]
        while end > start, trailingPunctuation.contains(text[text.index(before: end)]) {
            end = text.index(before: end)
        }
        // 閉じ括弧は、対応する開き括弧がある分だけ含める。
        while end > start, text[text.index(before: end)] == ")" {
            let slice = text[start..<end]
            let unbalanced = slice.count(where: { $0 == ")" }) > slice.count(where: { $0 == "(" })
            guard unbalanced else { break }
            end = text.index(before: end)
        }

        // スキームだけ、あるいはドメインにドットが無いものはリンクにしない。
        guard text.distance(from: start, to: end) > prefix.count else { return nil }
        guard text[start..<end].contains(".") else { return nil }
        return start..<end
    }

    /// 山括弧の無いメールアドレス。`@` を起点に前後へ伸ばす。
    private static func emailAutolink(
        _ text: String,
        at atSign: String.Index,
        rangeStart: String.Index,
        limit: String.Index
    ) -> Range<String.Index>? {
        var start = atSign
        while start > rangeStart {
            let previous = text.index(before: start)
            let character = text[previous]
            guard isEmailLocalCharacter(character) else { break }
            start = previous
        }
        guard start < atSign, isAutolinkBoundary(text, before: start, rangeStart: rangeStart) else { return nil }

        let domainStart = text.index(after: atSign)
        var end = domainStart
        while end < limit, isEmailDomainCharacter(text[end]) {
            end = text.index(after: end)
        }
        // 末尾の区切り文字はドメインに含めない。
        while end > domainStart, ".-_".contains(text[text.index(before: end)]) {
            end = text.index(before: end)
        }
        guard end > domainStart, text[domainStart..<end].contains(".") else { return nil }
        return start..<end
    }

    private static func isEmailLocalCharacter(_ character: Character) -> Bool {
        (character.isASCII && (character.isLetter || character.isNumber)) || "._+-".contains(character)
    }

    private static func isEmailDomainCharacter(_ character: Character) -> Bool {
        (character.isASCII && (character.isLetter || character.isNumber)) || ".-_".contains(character)
    }

    /// オートリンクを始められる位置か。単語の途中からは始まらない。
    private static func isAutolinkBoundary(
        _ text: String,
        before index: String.Index,
        rangeStart: String.Index
    ) -> Bool {
        guard index > rangeStart else { return true }
        let previous = text[text.index(before: index)]
        return previous.isWhitespace || "*_~([".contains(previous)
    }

    /// 大文字小文字を無視した前方一致。文字列全体を小文字化しないための補助。
    private static func hasPrefix(
        _ prefix: String,
        in text: String,
        at start: String.Index,
        limit: String.Index
    ) -> Bool {
        var index = start
        for expected in prefix {
            guard index < limit, text[index].lowercased() == String(expected) else { return false }
            index = text.index(after: index)
        }
        return true
    }

    // MARK: - 共通

    private static func endOfRun(
        _ text: String,
        from start: String.Index,
        of character: Character,
        limit: String.Index
    ) -> String.Index {
        var index = start
        while index < limit, text[index] == character {
            index = text.index(after: index)
        }
        return index
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }
}
