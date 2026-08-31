import Foundation

/// Markdown をハイライト用のトークン列に変換する。
///
/// 値型で状態を持たないため、どのスレッドからでも呼べる。
public struct MarkdownTokenizer: Sendable {

    public init() {}

    /// 文書全体をトークン化する。
    public func tokenize(_ text: String) -> [MarkdownToken] {
        tokenizeLines(text).flatMap(\.tokens)
    }

    /// 文書全体を、行ごとの結果とブロック状態つきでトークン化する。
    ///
    /// 差分更新を行う場合は、変更された行から `tokenizeLine(_:range:stateBefore:)` を
    /// 呼び直し、`stateAfter` が以前の値と一致した行で打ち切ればよい。
    public func tokenizeLines(_ text: String) -> [MarkdownLineTokens] {
        var state = MarkdownBlockState.blank
        let lines = LineScanner.scan(text)
        var result: [MarkdownLineTokens] = []
        result.reserveCapacity(lines.count)

        for (offset, line) in lines.enumerated() {
            let tokenized = tokenizeLine(
                text,
                range: line.content,
                stateBefore: state,
                nextLine: offset + 1 < lines.count ? lines[offset + 1].content : nil
            )
            state = tokenized.stateAfter
            result.append(tokenized)
        }
        return result
    }

    /// 1行だけをトークン化する。結果は `stateBefore` と `nextLine` にのみ依存する。
    ///
    /// - Parameters:
    ///   - text: 行が属する文字列全体。
    ///   - range: 改行文字を含まない行本体の範囲。
    ///   - stateBefore: 直前の行を処理し終えた時点のブロック状態。
    ///   - nextLine: 次の行の範囲。表のヘッダ行は「次の行が区切り行である」ことでしか
    ///     判別できないため、1行だけ先読みする。渡さなければ表は始まらない。
    public func tokenizeLine(
        _ text: String,
        range: Range<String.Index>,
        stateBefore: MarkdownBlockState,
        nextLine: Range<String.Index>? = nil
    ) -> MarkdownLineTokens {
        var tokens: [MarkdownToken] = []
        let stateAfter = appendBlock(
            text, range, state: stateBefore, nextLine: nextLine, depth: 0, into: &tokens
        )
        return MarkdownLineTokens(
            range: range,
            stateBefore: stateBefore,
            stateAfter: stateAfter,
            tokens: tokens
        )
    }

    // MARK: - ブロック解析

    /// 引用のネストをたどる深さの上限。`>>>>>...` で再帰が深くなるのを防ぐ。
    private static let maximumQuoteDepth = 8

    private func appendBlock(
        _ text: String,
        _ range: Range<String.Index>,
        state: MarkdownBlockState,
        nextLine: Range<String.Index>?,
        depth: Int,
        into tokens: inout [MarkdownToken]
    ) -> MarkdownBlockState {

        // フェンスが開いている間は、閉じフェンス以外のすべてをコードとして扱う。
        if case .fencedCode(let marker, let length) = state {
            if let closing = BlockScanner.closingFence(text, range, marker: marker, minimumLength: length) {
                tokens.append(MarkdownToken(kind: .marker(.codeFence), range: closing))
                return .blank
            }
            if !range.isEmpty {
                tokens.append(MarkdownToken(kind: .codeBlock, range: range))
            }
            return state
        }

        // HTML コメントが開いたまま。`-->` が来るまで、何が書いてあってもコメント。
        // **空行では終わらない。** ここで終わらせると、コメントの中に空行を置けなくなる。
        if case .htmlComment(let insideParagraph) = state {
            guard let closing = BlockScanner.htmlCommentClose(text, range) else {
                if !range.isEmpty {
                    tokens.append(MarkdownToken(kind: .htmlComment, range: range))
                }
                return state
            }

            // 行頭から始まったコメント（HTML ブロック）は、閉じた行がまるごとコメント。
            guard insideParagraph else {
                tokens.append(MarkdownToken(kind: .htmlComment, range: range))
                return .blank
            }

            // 段落の途中から始まったコメントは、`-->` のあとに本文が続く。
            tokens.append(
                MarkdownToken(kind: .htmlComment, range: range.lowerBound..<closing.upperBound)
            )
            let rest = closing.upperBound..<range.upperBound
            let stillOpen = InlineScanner.appendTokens(text, rest, into: &tokens)
            return stillOpen ? .htmlComment(insideParagraph: true) : .paragraph
        }

        // 表の区切り行。ヘッダ行を読んだ時点で先読み済みなので、ここでは必ず成立する。
        if case .tableDelimiterExpected(let columnCount) = state,
           let row = TableScanner.row(text, range), TableScanner.isDelimiterRow(text, row) {
            appendTableRow(text, row, cellKind: .tableDelimiterCell, parseInline: false, into: &tokens)
            return .tableBody(columnCount: columnCount)
        }

        // 表の本体。空行か別のブロックの開始で終わる。
        if case .tableBody(let columnCount) = state {
            if let row = tableBodyRow(text, range) {
                appendTableRow(text, row, cellKind: .tableCell, parseInline: true, into: &tokens)
                return .tableBody(columnCount: columnCount)
            }
        }

        let (indent, contentStart) = BlockScanner.measureIndent(text, range)

        // 空行。
        if contentStart == range.upperBound {
            return .blank
        }

        // 空行に見えるのに、空行にならない行。**印だけ付けて、解釈は変えない。**
        // ここで段落を切ってしまうと、エディタの表示とプレビューがずれる。
        // 見えていないものを見えるようにするだけで、意味には触らない。
        if let invisible = BlockScanner.invisibleBlankLine(text, range) {
            tokens.append(MarkdownToken(kind: .invisibleWhitespace, range: invisible))
        }

        let body = contentStart..<range.upperBound

        if indent >= 4 {
            // インデントによるコードブロック。
            if state == .blank || state == .indentedCode {
                tokens.append(MarkdownToken(kind: .codeBlock, range: range))
                return .indentedCode
            }
            // **入れ子のリストは、深くても印として扱う。**
            //
            // 行だけを見ていると、4つ以上のインデントは「インデントによる
            // コードブロック」と区別が付かない。ただし直前が段落（＝リストの行の
            // 次の状態）なら、それは親の項目の続きであって、コードブロックは始まらない。
            // その位置に印があれば入れ子のリストで、印として塗るのが正しい。
            //
            // これをやらないと、深い項目の `-` や `1.` だけが本文の色になる（実測）。
            if BlockScanner.listMarker(text, body) != nil {
                return appendListItem(text, body, into: &tokens)
            }

            // 段落の途中なら遅延継続行。ブロック記法は開始しない。
            let stillOpen = InlineScanner.appendTokens(text, body, into: &tokens)
            return stillOpen ? .htmlComment(insideParagraph: true) : .paragraph
        }

        // 引用。`>` を剥がして、残りを同じ規則で解析する。
        if text[contentStart] == ">", depth < Self.maximumQuoteDepth {
            var markerEnd = text.index(after: contentStart)
            if markerEnd < range.upperBound, text[markerEnd] == " " {
                markerEnd = text.index(after: markerEnd)
            }
            tokens.append(MarkdownToken(kind: .marker(.blockQuote), range: contentStart..<markerEnd))

            let inner = markerEnd..<range.upperBound
            if !inner.isEmpty {
                tokens.append(MarkdownToken(kind: .blockQuote, range: inner))
            }
            return appendBlock(
                text, inner, state: .blank, nextLine: nil, depth: depth + 1, into: &tokens
            )
        }

        // HTML コメントの始まり。**見出しやリストより先に見る。**
        // コメントの中身は Markdown として解釈しない。
        if let comment = BlockScanner.htmlCommentOpen(text, body) {
            tokens.append(MarkdownToken(kind: .htmlComment, range: range))
            return comment == .closedOnSameLine ? .blank : .htmlComment(insideParagraph: false)
        }

        // 開始フェンス。
        if let fence = BlockScanner.openingFence(text, body) {
            tokens.append(MarkdownToken(kind: .marker(.codeFence), range: fence.markerRange))
            if !fence.infoRange.isEmpty {
                tokens.append(MarkdownToken(kind: .codeLanguage, range: fence.infoRange))
            }
            return .fencedCode(marker: fence.marker, length: fence.length)
        }

        // 水平線。リストマーカーより先に判定する（`- - -` は水平線）。
        if let breakRange = BlockScanner.thematicBreak(text, body) {
            tokens.append(MarkdownToken(kind: .marker(.thematicBreak), range: breakRange))
            return .blank
        }

        // ATX 見出し。
        if let heading = BlockScanner.atxHeading(text, body) {
            tokens.append(MarkdownToken(kind: .marker(.heading), range: heading.markerRange))
            if !heading.textRange.isEmpty {
                tokens.append(MarkdownToken(kind: .heading(level: heading.level), range: heading.textRange))
                InlineScanner.appendTokens(text, heading.textRange, into: &tokens)
            }
            if let closing = heading.closingRange {
                tokens.append(MarkdownToken(kind: .marker(.heading), range: closing))
            }
            return .blank
        }

        // リスト項目。チェックボックスが続けばタスクリスト。
        if BlockScanner.listMarker(text, body) != nil {
            return appendListItem(text, body, into: &tokens)
        }

        // 表のヘッダ行。次の行が列数の一致する区切り行のときだけ成立する。
        if let header = tableHeaderRow(text, body, nextLine: nextLine) {
            appendTableRow(text, header, cellKind: .tableHeaderCell, parseInline: true, into: &tokens)
            return .tableDelimiterExpected(columnCount: header.cells.count)
        }

        // 通常の段落。
        let stillOpen = InlineScanner.appendTokens(text, body, into: &tokens)
        return stillOpen ? .htmlComment(insideParagraph: true) : .paragraph
    }

    // MARK: - 表（GFM）

    /// 次の行が列数の一致する区切り行であれば、この行は表のヘッダ行。
    private func tableHeaderRow(
        _ text: String,
        _ range: Range<String.Index>,
        nextLine: Range<String.Index>?
    ) -> TableScanner.Row? {
        guard let nextLine,
              let header = TableScanner.row(text, range),
              let delimiter = TableScanner.row(text, nextLine),
              TableScanner.isDelimiterRow(text, delimiter),
              delimiter.cells.count == header.cells.count
        else { return nil }
        return header
    }

    /// 表の本体として読める行か。別のブロックが始まる行では表を終わらせる。
    private func tableBodyRow(_ text: String, _ range: Range<String.Index>) -> TableScanner.Row? {
        let (indent, contentStart) = BlockScanner.measureIndent(text, range)
        guard indent < 4, contentStart < range.upperBound else { return nil }

        let body = contentStart..<range.upperBound
        guard text[contentStart] != ">",
              BlockScanner.openingFence(text, body) == nil,
              BlockScanner.thematicBreak(text, body) == nil,
              BlockScanner.atxHeading(text, body) == nil
        else { return nil }

        return TableScanner.row(text, range)
    }

    private func appendTableRow(
        _ text: String,
        _ row: TableScanner.Row,
        cellKind: MarkdownToken.Kind,
        parseInline: Bool,
        into tokens: inout [MarkdownToken]
    ) {
        // パイプとセルは同じ階層なので、位置順に並べて出す。
        let segments = row.pipes.map { (range: $0, isCell: false) }
            + row.cells.filter { !$0.isEmpty }.map { (range: $0, isCell: true) }

        for segment in segments.sorted(by: { $0.range.lowerBound < $1.range.lowerBound }) {
            guard segment.isCell else {
                tokens.append(MarkdownToken(kind: .marker(.tablePipe), range: segment.range))
                continue
            }
            tokens.append(MarkdownToken(kind: cellKind, range: segment.range))
            if parseInline {
                InlineScanner.appendTokens(text, segment.range, into: &tokens)
            }
        }
    }

    /// リスト項目を1つ分、トークンにする。**深さに関わらず同じ扱い。**
    ///
    /// 行頭から数えたインデントが4以上でも、直前が段落なら入れ子のリストなので、
    /// ここを通す。印を本文の色で塗らないための共通経路。
    private func appendListItem(
        _ text: String, _ body: Range<String.Index>, into tokens: inout [MarkdownToken]
    ) -> MarkdownBlockState {
        guard let list = BlockScanner.listMarker(text, body) else { return .paragraph }
        tokens.append(MarkdownToken(kind: .marker(.list), range: list.markerRange))
        var content = list.contentRange
        if let task = BlockScanner.taskMarker(text, content) {
            tokens.append(MarkdownToken(kind: .taskMarker(isChecked: task.isChecked), range: task.range))
            content = task.contentRange
        }
        let stillOpen = InlineScanner.appendTokens(text, content, into: &tokens)
        return stillOpen ? .htmlComment(insideParagraph: true) : .paragraph
    }

}
