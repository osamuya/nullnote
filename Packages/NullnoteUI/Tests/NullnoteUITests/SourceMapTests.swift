#if canImport(AppKit)
import AppKit
import MarkdownCore
import Testing
@testable import NullnoteUI

/// 本文とプレビューの文字の対応（#M0045）。
///
/// プレビューで選んだところを本文の範囲に、本文で選んだところをプレビューの範囲に
/// 写せるかを確かめる。範囲は文字で書いて、文字で確かめる。
@Suite("本文とプレビューの文字の対応")
@MainActor
struct SourceMapTests {

    let theme = MarkdownTheme.standard()

    /// 本文を組み、`blockIndex` 番目のブロックの文字（テキストビューに載るもの）を返す。
    func preview(_ source: String, block blockIndex: Int = 0) -> NSAttributedString {
        let blocks = PreviewBuilder.build(source, theme: theme)
        guard blockIndex < blocks.count else { return NSAttributedString() }
        let text: AttributedString
        switch blocks[blockIndex].content {
        case .paragraph(let value), .heading(_, let value): text = value
        default: return NSAttributedString()
        }
        return PreviewAttributes.make(from: text, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text)
    }

    /// プレビューで `selected` を選んだとき、本文のどこになるか。
    func sourceText(selecting selected: String, in source: String, block: Int = 0) -> String? {
        let shown = preview(source, block: block)
        let range = (shown.string as NSString).range(of: selected)
        guard range.location != NSNotFound,
              let mapped = PreviewSourceIndex(shown).sourceRange(forPreview: range)
        else { return nil }
        return (source as NSString).substring(with: mapped)
    }

    /// 本文で `selected` を選んだとき、プレビューのどこに色が付くか。
    func previewText(selecting selected: String, in source: String, block: Int = 0) -> [String] {
        let shown = preview(source, block: block)
        let range = (source as NSString).range(of: selected)
        return PreviewSourceIndex(shown).previewRanges(forSource: [range]).map {
            (shown.string as NSString).substring(with: $0)
                .replacingOccurrences(of: PreviewAttributes.leadingSpacer, with: "")
        }
    }

    // MARK: - プレビュー → 本文

    @Test("ただの文字は、そのまま本文の同じ文字になる")
    func plain() {
        #expect(sourceText(selecting: "表示回数", in: "従来の表示回数に近い") == "表示回数")
    }

    @Test("太字の中を選ぶと、記号の内側だけになる")
    func insideStrong() {
        #expect(sourceText(selecting: "大雑把な", in: "かつての**大雑把な**アクセス数") == "大雑把な")
    }

    @Test("記号をまたいで選ぶと、本文では記号も含めて一続きになる")
    func acrossMarkers() {
        #expect(sourceText(selecting: "通太", in: "普通**太字**です") == "通**太")
    }

    @Test("インラインコードは、頭の幅ゼロの文字を数えない")
    func inlineCode() {
        #expect(sourceText(selecting: "_ga", in: "Cookie には `_ga` という値") == "_ga")
    }

    @Test("リンクは見えている文字だけが対応する")
    func link() {
        #expect(sourceText(selecting: "公式", in: "詳しくは[公式の説明](https://example.com)へ") == "公式")
    }

    @Test("見出しは # を数えない。前の行が日本語でもずれない")
    func headingAfterJapanese() {
        let source = "かつての大雑把なアクセス数\n\n## では、どのように解釈するのか？\n"
        #expect(sourceText(selecting: "どのように", in: source, block: 1) == "どのように")
    }

    @Test("絵文字（UTF-16 で2つ分）のあとでもずれない")
    func afterSurrogatePair() {
        #expect(sourceText(selecting: "あいう", in: "😀 と **あいう** と") == "あいう")
    }

    @Test("逃がし文字を含む並びは、丸ごと対応させる")
    func escapedFallsBackToWhole() {
        // `\*` は本文で2文字、プレビューで1文字。1文字ずつは合わせられない。
        let mapped = sourceText(selecting: "b", in: "a\\*b")
        #expect(mapped == "a\\*b")
    }

    // MARK: - 本文 → プレビュー

    @Test("本文で記号ごと選んでも、プレビューでは文字だけに色が付く")
    func strongToPreview() {
        #expect(previewText(selecting: "**大雑把な**", in: "かつての**大雑把な**アクセス数") == ["大雑把な"])
    }

    @Test("記号をまたいだ選択は、プレビューで一続きに色が付く")
    func acrossToPreview() {
        #expect(previewText(selecting: "通**太", in: "普通**太字**です") == ["通太"])
    }

    @Test("インラインコードの中を選ぶと、プレビューの同じ文字に色が付く")
    func codeToPreview() {
        #expect(previewText(selecting: "_ga", in: "Cookie には `_ga` という値") == ["_ga"])
    }

    @Test("ほかの段落を選んでも、この段落には色が付かない")
    func otherBlock() {
        let source = "一つ目の段落\n\n二つ目の段落\n"
        #expect(previewText(selecting: "二つ目", in: source, block: 0).isEmpty)
        #expect(previewText(selecting: "二つ目", in: source, block: 1) == ["二つ目"])
    }

    @Test("段落をまたいだ選択は、それぞれの段落の中だけに色が付く")
    func acrossBlocks() {
        let source = "一つ目の段落\n\n二つ目の段落\n"
        #expect(previewText(selecting: "段落\n\n二つ目", in: source, block: 0) == ["段落"])
        #expect(previewText(selecting: "段落\n\n二つ目", in: source, block: 1) == ["二つ目"])
    }

    @Test("合流の印のあとの段落も、本文の位置でずれない")
    func afterConflictMarkers() {
        let source = """
        前
        \(ThreeWayMerge.ourMarker)
        こちら
        \(ThreeWayMerge.separator)
        あちら
        \(ThreeWayMerge.theirMarker)
        印のあとの段落
        """
        let blocks = PreviewBuilder.build(source, theme: theme)
        guard let last = blocks.last, case .paragraph(let text) = last.content else {
            Issue.record("最後の段落が無い"); return
        }
        let shown = PreviewAttributes.make(from: text, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text)
        let range = (shown.string as NSString).range(of: "あとの")
        let mapped = PreviewSourceIndex(shown).sourceRange(forPreview: range)
        #expect(mapped.map { (source as NSString).substring(with: $0) } == "あとの")
    }

    // MARK: - 行と列

    @Test("列は UTF-8 のバイト数で数えられている")
    func utf8Columns() {
        let converter = SourcePositionConverter("あいう\nかきく")
        // 「き」は2行目の4バイト目から（「か」が3バイト）。
        #expect(converter.offset(line: 2, column: 4) == 5)
        #expect(converter.offset(line: 1, column: 1) == 0)
        #expect(converter.offset(line: 3, column: 1) == nil)
    }
}
#endif
