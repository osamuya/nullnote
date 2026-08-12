#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

/// 差分ハイライトの検証。
///
/// **「速いか」ではなく「全文貼り直しと同じ結果になるか」を縛る。**
/// 差分更新のこわいところは、状態を持ち越し損ねて後ろの行の色が狂うこと。
/// 目で見て気づけない（画面外で起きる）ので、機械的に比べる。
@Suite("差分ハイライト")
@MainActor
struct IncrementalHighlightTests {

    let theme = MarkdownTheme.standard()

    /// `before` を貼ったあと編集し、差分で貼り直した結果と、
    /// 編集後の本文を最初から貼った結果を比べる。
    func expectSameAsFullRepaint(
        _ before: String,
        edit: NSRange,
        with insertion: String,
        _ comment: Comment? = nil,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var incremental = MarkdownHighlighter(theme: theme)
        let storage = NSTextStorage(string: before)
        incremental.apply(to: storage, text: before)

        storage.replaceCharacters(in: edit, with: insertion)
        let after = storage.string
        incremental.apply(
            to: storage,
            text: after,
            edited: NSRange(location: edit.location, length: (insertion as NSString).length)
        )

        var full = MarkdownHighlighter(theme: theme)
        let expected = NSTextStorage(string: after)
        full.apply(to: expected, text: after)

        #expect(storage.isEqual(to: expected), comment, sourceLocation: sourceLocation)
    }

    // MARK: - ふつうの編集

    @Test("段落の途中に1文字打つ")
    func typeInParagraph() {
        let source = "# 見出し\n\n本文です。\n\nもう一段落。\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 8, length: 0), with: "あ")
    }

    @Test("見出しの記号を足す")
    func addHeadingMarker() {
        // 行の種類そのものが変わる。その行だけ貼り直せば足りる。
        let source = "本文\n\nつぎ\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 0, length: 0), with: "## ")
    }

    @Test("改行を入れて行を分ける")
    func splitLine() {
        let source = "# 見出し\n\n長い本文をここで割る\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 11, length: 0), with: "\n")
    }

    @Test("行を消す")
    func deleteLine() {
        let source = "# 見出し\n\n消える行\n残る行\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 7, length: 5), with: "")
    }

    @Test("先頭に打つ")
    func typeAtStart() {
        expectSameAsFullRepaint("本文\n", edit: NSRange(location: 0, length: 0), with: "あ")
    }

    @Test("末尾に打つ")
    func typeAtEnd() {
        let source = "本文\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 3, length: 0), with: "あ")
    }

    // MARK: - 状態が後ろへ伝播する編集

    @Test("コードフェンスを開くと、後ろ全部の見え方が変わる")
    func openingFenceAffectsRest() {
        // ここが差分更新のいちばんこわいところ。
        // 1行足しただけで、文書の最後までコードブロックになる。
        let source = "# 見出し\n\n本文\n\n**強調**\n\n`コード`\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 7, length: 0), with: "```\n")
    }

    @Test("コードフェンスを閉じると、後ろが本文に戻る")
    func closingFenceAffectsRest() {
        let source = "```\nlet x = 1\n\n**強調**\n\n本文\n"
        // 2行目の後ろに閉じフェンスを足す。
        expectSameAsFullRepaint(source, edit: NSRange(location: 14, length: 0), with: "```\n")
    }

    @Test("フェンスの言語を変えると、中の色分けが変わる")
    func changingFenceLanguage() {
        let source = "```\nlet x = 1 // メモ\nprint(x)\n```\n\n本文\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 3, length: 0), with: "swift")
    }

    @Test("ブロックコメントを開くと、次の行まで色が続く")
    func blockCommentSpansLines() {
        let source = "```swift\nlet x = 1\nlet y = 2\n```\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 9, length: 0), with: "/*\n")
    }

    // MARK: - 1行先を見る記法（表）

    @Test("区切り行を足すと、1行**手前**が表の見出しになる")
    func tableDelimiterChangesPreviousLine() {
        // 表のヘッダは「次の行が区切り行か」でしか決まらない。
        // 編集した行だけ貼り直すと、手前の行が本文のまま残る。
        let source = "| 項目 | 値 |\n本文\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 9, length: 0), with: "|---|---|\n")
    }

    @Test("区切り行を消すと、表でなくなる")
    func removingDelimiter() {
        let source = "| 項目 | 値 |\n|---|---|\n| あ | い |\n\n本文\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 9, length: 10), with: "")
    }

    @Test("表に行を足す")
    func addTableRow() {
        let source = "| 項目 | 値 |\n|---|---|\n| あ | い |\n\n本文\n"
        expectSameAsFullRepaint(source, edit: NSRange(location: 19, length: 0), with: "| う | え |\n")
    }

    // MARK: - 続けて打つ

    @Test("続けて打っても結果が全文貼り直しと一致する")
    func repeatedEdits() {
        var incremental = MarkdownHighlighter(theme: theme)
        let storage = NSTextStorage(string: "# 見出し\n\n本文\n")
        incremental.apply(to: storage, text: storage.string)

        // 1文字ずつ打ち足していく。実際の打鍵と同じ形。
        for character in "```swift\nlet x = 1\n" {
            let location = storage.length
            storage.replaceCharacters(in: NSRange(location: location, length: 0), with: String(character))
            incremental.apply(
                to: storage,
                text: storage.string,
                edited: NSRange(location: location, length: (String(character) as NSString).length)
            )
        }

        var full = MarkdownHighlighter(theme: theme)
        let expected = NSTextStorage(string: storage.string)
        full.apply(to: expected, text: expected.string)
        #expect(storage.isEqual(to: expected))
    }

    // MARK: - 全文に戻す経路

    @Test("編集範囲を渡さなければ全文を貼り直す")
    func nilEditedRepaintsEverything() {
        // テーマ変更や、外から本文が差し替わったときの経路。
        var highlighter = MarkdownHighlighter(theme: theme)
        let storage = NSTextStorage(string: "# 見出し\n\n本文\n")
        highlighter.apply(to: storage, text: storage.string)

        // 属性を全部消してから、範囲を渡さずに貼り直す。
        storage.setAttributes([:], range: NSRange(location: 0, length: storage.length))
        highlighter.apply(to: storage, text: storage.string)

        var full = MarkdownHighlighter(theme: theme)
        let expected = NSTextStorage(string: storage.string)
        full.apply(to: expected, text: expected.string)
        #expect(storage.isEqual(to: expected))
    }

    @Test("初回は範囲を渡されても全文を貼る")
    func firstPassIgnoresEditedRange() {
        // 前回の状態が無いので、比べる相手がいない。
        var highlighter = MarkdownHighlighter(theme: theme)
        let source = "# 見出し\n\n本文\n"
        let storage = NSTextStorage(string: source)
        highlighter.apply(to: storage, text: source, edited: NSRange(location: 8, length: 1))

        var full = MarkdownHighlighter(theme: theme)
        let expected = NSTextStorage(string: source)
        full.apply(to: expected, text: source)
        #expect(storage.isEqual(to: expected))
    }
}
#endif
