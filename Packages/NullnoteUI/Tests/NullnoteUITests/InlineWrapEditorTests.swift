#if canImport(AppKit)
import AppKit
import MarkdownCore
import Testing
@testable import NullnoteUI

/// 選んだところが記法で囲まれるか。
///
/// 何をどう囲むかの判断は `MarkdownCore` の `InlineWrap` にあり、
/// そちらでテストしてある。**ここで見るのは本文の書き換えと、選択の残り方。**
@Suite("記法で囲む（エディタ側）")
@MainActor
struct InlineWrapEditorTests {

    func makeTextView(_ text: String) -> FocusReportingTextView {
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = text
        return textView
    }

    // MARK: - 記号キー

    @Test("選んで * を押すと、消えずに囲まれる")
    func typeAsterisk() {
        let textView = makeTextView("Nullnote は速い")
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        textView.insertText("*", replacementRange: textView.selectedRange())
        #expect(textView.string == "*Nullnote* は速い")
    }

    @Test("囲んだあとも選ばれたままなので、重ねがけできる")
    func wrapTwice() {
        let textView = makeTextView("Nullnote")
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        textView.insertText("*", replacementRange: textView.selectedRange())
        textView.insertText("*", replacementRange: textView.selectedRange())
        #expect(textView.string == "**Nullnote**")
    }

    @Test("バッククォート・チルダ・角括弧でも囲める")
    func otherSymbols() {
        for (symbol, expected) in [("`", "`foo`"), ("~", "~foo~"), ("[", "[foo]")] {
            let textView = makeTextView("foo")
            textView.setSelectedRange(NSRange(location: 0, length: 3))
            textView.insertText(symbol, replacementRange: textView.selectedRange())
            #expect(textView.string == expected)
        }
    }

    /// **ふだんの打鍵は変えない。** 選択が無ければ、いつもどおり文字が入る。
    @Test("選択が無ければ、記号はそのまま入る")
    func noSelection() {
        let textView = makeTextView("foo")
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.insertText("*", replacementRange: textView.selectedRange())
        #expect(textView.string == "foo*")
    }

    @Test("割り当てていない記号は、選んでいても置き換わる")
    func unassignedSymbol() {
        let textView = makeTextView("foo")
        textView.setSelectedRange(NSRange(location: 0, length: 3))
        textView.insertText("_", replacementRange: textView.selectedRange())
        #expect(textView.string == "_")
    }

    // MARK: - ショートカット

    @Test("⌘B は太字にする")
    func strong() {
        let textView = makeTextView("Nullnote")
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        textView.wrapSelection(with: .strong)
        #expect(textView.string == "**Nullnote**")
    }

    @Test("⌘K はリンクにして、カーソルを行き先へ置く")
    func link() {
        let textView = makeTextView("Nullnote")
        textView.setSelectedRange(NSRange(location: 0, length: 8))
        textView.wrapSelection(with: .link)
        #expect(textView.string == "[Nullnote]()")
        textView.insertText("https://sabanote.com/", replacementRange: textView.selectedRange())
        #expect(textView.string == "[Nullnote](https://sabanote.com/)")
    }

    @Test("選択が無くても、記法だけ置いてあいだにカーソルが入る")
    func emptyStrong() {
        let textView = makeTextView("")
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.wrapSelection(with: .strong)
        #expect(textView.string == "****")
        textView.insertText("太字", replacementRange: textView.selectedRange())
        #expect(textView.string == "**太字**")
    }

    @Test("日本語も正しい位置で囲まれる")
    func japanese() {
        let textView = makeTextView("これは見出しです")
        textView.setSelectedRange(NSRange(location: 3, length: 3))   // 「見出し」
        textView.wrapSelection(with: .strong)
        #expect(textView.string == "これは**見出し**です")
    }
}
#endif
