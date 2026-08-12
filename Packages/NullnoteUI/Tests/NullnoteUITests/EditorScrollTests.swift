#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

@Suite("エディタのスクロール位置")
@MainActor
struct EditorScrollTests {

    /// 300 行のテキストを載せたスクロールビューを作る。
    func makeScrollView(text: String) -> (NSScrollView, NSTextView)? {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        guard let textView = scrollView.documentView as? NSTextView else { return nil }
        textView.textContainerInset = .zero
        textView.string = text
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        scrollView.layoutSubtreeIfNeeded()
        return (scrollView, textView)
    }

    @Test("スクロールすると先頭に見える文字の位置が進む")
    func topCharacterAdvancesWithScroll() throws {
        let text = (1...300).map { "line \($0)" }.joined(separator: "\n")
        let made = try #require(makeScrollView(text: text))
        let (scrollView, textView) = made

        let before = textView.topVisibleCharacterIndex
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 600))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        let after = textView.topVisibleCharacterIndex

        #expect(before == 0)
        #expect(after > before)
    }

    @Test("先頭の文字位置から求めた行番号が、スクロール量と一緒に増える")
    func topLineAdvancesWithScroll() throws {
        let text = (1...300).map { "line \($0)" }.joined(separator: "\n")
        let made = try #require(makeScrollView(text: text))
        let (scrollView, textView) = made
        let index = LineIndex(text)

        var previousLine = index.line(atUTF16Offset: textView.topVisibleCharacterIndex)
        #expect(previousLine == 1)

        for offset in stride(from: 200, through: 1000, by: 200) {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(offset)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            let line = index.line(atUTF16Offset: textView.topVisibleCharacterIndex)
            #expect(line >= previousLine, "スクロールしたのに行番号が戻った: \(previousLine) → \(line)")
            previousLine = line
        }
        // 1000pt も送れば、確実に最初の行より下にいる。
        #expect(previousLine > 1)
    }
}

/// テキストビューを組み立てる順序の検証。
///
/// `NSTextView.textColor` と `font` は**本文全体**を塗り替える。
/// ハイライトを適用したあとにこれらを設定すると、装飾が消えてしまう。
/// 「開いた直後だけ色が付かず、一度編集すると色が付く」という症状になる。
@Suite("エディタの組み立て順")
@MainActor
struct EditorSetupOrderTests {

    let source = "# 見出し\n\n本文と `コード`。\n"

    func makeTextView(theme: MarkdownTheme) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isRichText = false
        return textView
    }

    /// 見出しの色を読む。ハイライトが効いていれば heading 色になる。
    func headingColor(of textView: NSTextView, theme: MarkdownTheme) -> NSColor? {
        let range = (textView.string as NSString).range(of: "見出し")
        guard range.location != NSNotFound else { return nil }
        return textView.textStorage?.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    @Test("正しい順序（テーマ → 本文 → ハイライト）なら装飾が残る")
    func correctOrderKeepsHighlighting() throws {
        let theme = MarkdownTheme.standard()
        let textView = makeTextView(theme: theme)

        textView.string = source
        textView.font = theme.bodyFont
        textView.textColor = theme.text
        var highlighter = MarkdownHighlighter(theme: theme); highlighter.apply(to: try #require(textView.textStorage), text: source)

        #expect(headingColor(of: textView, theme: theme) === theme.heading)
    }

    @Test("誤った順序（ハイライトのあとに textColor）だと装飾が消える")
    func wrongOrderWipesHighlighting() throws {
        let theme = MarkdownTheme.standard()
        let textView = makeTextView(theme: theme)

        textView.string = source
        var highlighter = MarkdownHighlighter(theme: theme); highlighter.apply(to: try #require(textView.textStorage), text: source)
        textView.textColor = theme.text   // ← これが全体を塗り替える

        // 見出しの色が本文の色になってしまう。この挙動を記録しておく。
        #expect(headingColor(of: textView, theme: theme) === theme.text)
    }
}
#endif
