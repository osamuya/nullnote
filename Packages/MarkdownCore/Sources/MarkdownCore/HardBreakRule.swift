import Foundation

/// 改行のときに、行末へ半角スペース2つを入れるか（#015・D-79）。
///
/// Markdown では、行末の半角スペース2つが「段落の中の改行」の印になる。
/// これを本文に入れておけば、コピーしてほかのエディタに貼っても、
/// プレビューの設定に関わらず、書いたとおりの位置で改行される。
///
/// **副作用を持たない。** 判断だけをここに集めて、テストで縛る。
/// 実際に本文を書き換えるのは呼ぶ側（`FocusReportingTextView.insertNewline`）。
///
/// | Return を押した行 | 入れるか |
/// |---|---|
/// | 文字のある普通の行 | 入れる |
/// | 引用の行（`> 文`） | 入れる |
/// | リストの行（`- 項目`） | 入れない。次の行は新しい項目になる |
/// | 空の行・見出し・水平線・コードフェンス | 入れない |
/// | 表・コードブロック・コメントの中 | 入れない |
/// | すでに行末が空白2つ以上か `\` | 入れない。空白1つなら1つだけ足す |
public enum HardBreakRule {

    /// 改行の前（カーソルの位置）に入れる空白。入れないときは空の文字列。
    ///
    /// - Parameters:
    ///   - line: いまカーソルがある行。**改行文字を含まない。**
    ///   - caretUTF16Offset: 行頭から数えたカーソルの位置。行の途中で押したときは、
    ///     カーソルより前が改行の前の行になる。
    ///   - continuation: 同じ改行について `LineContinuationRule` が決めたこと。
    ///   - isInsideCode: コードブロックの中か。
    ///   - blockState: この行を打ち始める前のブロック状態。
    public static func spaces(
        line: String, caretUTF16Offset caret: Int, continuation: LineContinuation,
        isInsideCode: Bool = false, blockState: MarkdownBlockState = .blank
    ) -> String {
        // コードの中の空白は、改行の印ではなくコードの中身になる。
        guard !isInsideCode else { return "" }
        switch blockState {
        case .indentedCode, .fencedCode, .tableDelimiterExpected, .tableBody,
             .htmlComment, .conflictOurs, .conflictTheirs:
            return ""
        case .blank, .paragraph:
            break
        }

        // 抜ける・表の行を足す・フェンスを閉じる改行は、改行の印と関係が無い。
        switch continuation {
        case .plain, .carry: break
        case .end, .tableRow, .openFence: return ""
        }

        // 改行の前の行になるのは、カーソルより前の部分。
        let utf16 = line.utf16
        guard caret <= utf16.count,
              let end = utf16.index(utf16.startIndex, offsetBy: caret, limitedBy: utf16.endIndex)?
                .samePosition(in: line)
        else { return "" }
        let head = line[..<end]
        guard head.contains(where: { !$0.isWhitespace }) else { return "" }

        // 行の種類は行全体で見る（カーソルの位置で変わらない）。
        let (indent, contentStart) = BlockScanner.measureIndent(line, line.startIndex..<line.endIndex)
        // 段落の後ろでない4カラム以上の字下げは、コードブロック。
        if indent >= 4, blockState == .blank { return "" }
        let body = contentStart..<line.endIndex
        if BlockScanner.atxHeading(line, body) != nil
            || BlockScanner.thematicBreak(line, body) != nil
            || BlockScanner.openingFence(line, body) != nil {
            return ""
        }
        let inner = afterQuoteMarkers(line, from: contentStart)
        if BlockScanner.listMarker(line, inner..<line.endIndex) != nil { return "" }
        // 表の行。`|` で始まる行は、見出しを書いている途中かもしれない。
        if inner < line.endIndex, line[inner] == "|" { return "" }

        // すでに改行の印がある。
        if head.hasSuffix("\\") { return "" }
        let trailing = head.reversed().prefix(while: { $0 == " " }).count
        switch trailing {
        case 0: return "  "
        case 1: return " "
        default: return ""
        }
    }

    /// 引用の `>` と、そのあいだの空白を読み飛ばした位置。
    private static func afterQuoteMarkers(_ line: String, from start: String.Index) -> String.Index {
        var cursor = start
        while cursor < line.endIndex, line[cursor] == ">" {
            cursor = line.index(after: cursor)
            while cursor < line.endIndex, line[cursor] == " " || line[cursor] == "\t" {
                cursor = line.index(after: cursor)
            }
        }
        return cursor
    }
}
