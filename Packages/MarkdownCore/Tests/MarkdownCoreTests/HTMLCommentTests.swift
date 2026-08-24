import Testing
@testable import MarkdownCore

/// HTML コメント `<!-- … -->`。
///
/// プレビューには出さない。エディタでは薄く出す。
/// **中身は Markdown として解釈しない**ので、コメントに入れた見出しは
/// 見出し色にならず、目次にも出ない。
@Suite("HTML コメント")
struct HTMLCommentTests {

    @Test("行頭で開いて同じ行で閉じる")
    func singleLine() {
        #expect(MarkdownTokenizer.snapshot("<!-- メモ -->") == [
            TokenSnapshot(.htmlComment, "<!-- メモ -->")
        ])
    }

    @Test("複数行にまたがる")
    func multipleLines() {
        let source = "<!--\nメモ1\nメモ2\n-->\n"
        #expect(MarkdownTokenizer.lineSnapshots(source).prefix(4) == [
            [TokenSnapshot(.htmlComment, "<!--")],
            [TokenSnapshot(.htmlComment, "メモ1")],
            [TokenSnapshot(.htmlComment, "メモ2")],
            [TokenSnapshot(.htmlComment, "-->")],
        ])
    }

    @Test("中の見出しやリストは記法として解釈しない")
    func contentsAreNotMarkdown() {
        // 節ごとコメントアウトする使い方。ここで `##` が見出しになると、
        // 目次に出てしまい、外したはずの節が残る。
        let source = "<!--\n## 外した節\n- 項目\n-->\n"
        let lines = MarkdownTokenizer.lineSnapshots(source)
        #expect(lines[1] == [TokenSnapshot(.htmlComment, "## 外した節")])
        #expect(lines[2] == [TokenSnapshot(.htmlComment, "- 項目")])
    }

    @Test("空行では終わらない")
    func blankLineDoesNotClose() {
        // コメントの中に空行を置けないと、節をまとめて外せない。
        let source = "<!--\n\n本文\n-->\n"
        let lines = MarkdownTokenizer().tokenizeLines(source)
        #expect(lines[1].stateAfter == .htmlComment(insideParagraph: false))
        #expect(lines[2].stateAfter == .htmlComment(insideParagraph: false))
        #expect(lines[3].stateAfter == .blank)
    }

    @Test("閉じ忘れたら文書の終わりまで")
    func unclosedRunsToEnd() {
        let source = "<!-- 閉じ忘れ\n本文A\n本文B\n"
        let lines = MarkdownTokenizer.lineSnapshots(source)
        #expect(lines[1] == [TokenSnapshot(.htmlComment, "本文A")])
        #expect(lines[2] == [TokenSnapshot(.htmlComment, "本文B")])
    }

    @Test("段落を割り込める")
    func interruptsParagraph() {
        let source = "本文A\n<!-- メモ -->\n本文B\n"
        let lines = MarkdownTokenizer.lineSnapshots(source)
        #expect(lines[1] == [TokenSnapshot(.htmlComment, "<!-- メモ -->")])
        #expect(lines[2].isEmpty, "コメントのあとがコメント扱いのまま残っている")
    }

    // MARK: - 本文の途中

    @Test("段落の途中のコメント")
    func inlineComment() {
        #expect(MarkdownTokenizer.snapshot("本文の<!-- メモ -->途中です。") == [
            TokenSnapshot(.htmlComment, "<!-- メモ -->")
        ])
    }

    @Test("段落の途中で開いて、次の行で閉じる")
    func inlineCommentAcrossLines() {
        let source = "本文です。<!-- メモ\nつづき -->あと\n"
        let lines = MarkdownTokenizer().tokenizeLines(source)
        #expect(lines[0].stateAfter == .htmlComment(insideParagraph: true))
        // 閉じたあとは段落に戻る。`あと` までコメントにしない。
        #expect(lines[1].stateAfter == .paragraph)

        let snapshots = MarkdownTokenizer.lineSnapshots(source)
        #expect(snapshots[0] == [TokenSnapshot(.htmlComment, "<!-- メモ")])
        #expect(snapshots[1] == [TokenSnapshot(.htmlComment, "つづき -->")])
    }

    // MARK: - コメントにならない場所

    @Test("コードブロックの中はコメントにしない")
    func insideFencedCode() {
        let source = "```\n<!-- メモ -->\n```\n"
        #expect(MarkdownTokenizer.lineSnapshots(source)[1] == [
            TokenSnapshot(.codeBlock, "<!-- メモ -->")
        ])
    }

    @Test("インラインコードの中はコメントにしない")
    func insideCodeSpan() {
        let tokens = MarkdownTokenizer.snapshot("`<!-- メモ -->` です。")
        #expect(!tokens.contains { $0.kind == .htmlComment })
    }

    @Test("4字下げはコードブロックのまま")
    func indentedIsCode() {
        #expect(MarkdownTokenizer.snapshot("    <!-- メモ -->") == [
            TokenSnapshot(.codeBlock, "    <!-- メモ -->")
        ])
    }

    @Test("3字下げまではコメント")
    func slightIndentIsStillComment() {
        #expect(MarkdownTokenizer.snapshot("   <!-- メモ -->") == [
            TokenSnapshot(.htmlComment, "   <!-- メモ -->")
        ])
    }

    @Test("引用の中でも効く")
    func insideBlockQuote() {
        let tokens = MarkdownTokenizer.snapshot("> <!-- メモ -->")
        #expect(tokens.contains { $0.kind == .htmlComment })
    }
}
