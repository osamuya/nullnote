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
#endif
