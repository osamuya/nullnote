#if canImport(AppKit)
import AppKit
import MarkdownCore
import Testing
@testable import NullnoteUI

/// Tab と ⇧Tab で、リストの深さが変わるか。
///
/// 何文字入れる・外すかの判断は `MarkdownCore` の `IndentChange` にあり、
/// そちらでテストしてある。**ここで見るのは本文の書き換えと、設定の効き方。**
@Suite("リストの深さを変える（エディタ側）")
@MainActor
struct IndentChangeEditorTests {

    func makeTextView(_ text: String, unit: String = IndentStyle.fourSpaces.unit)
        -> FocusReportingTextView
    {
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = text
        textView.indentUnit = unit
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    @Test("Tab でリストが1段深くなる")
    func deepen() {
        let textView = makeTextView("1. foo")
        textView.insertTab(nil)
        #expect(textView.string == "    1. foo")
    }

    @Test("⇧Tab で1段戻る")
    func shallow() {
        let textView = makeTextView("    1. foo")
        textView.insertBacktab(nil)
        #expect(textView.string == "1. foo")
    }

    @Test("設定がタブなら、タブが入る")
    func tabUnit() {
        let textView = makeTextView("- foo", unit: IndentStyle.tab.unit)
        textView.insertTab(nil)
        #expect(textView.string == "\t- foo")
    }

    @Test("設定がスペース2なら、2つ入る")
    func twoSpaces() {
        let textView = makeTextView("- foo", unit: IndentStyle.twoSpaces.unit)
        textView.insertTab(nil)
        #expect(textView.string == "  - foo")
    }

    /// **浅くするときは設定を見ない。** 書かれているものを見て外す。
    @Test("タブ設定でも、スペースで書かれていればスペースを外す")
    func shallowIgnoresSetting() {
        let textView = makeTextView("    1. foo", unit: IndentStyle.tab.unit)
        textView.insertBacktab(nil)
        #expect(textView.string == "1. foo")
    }

    @Test("リストでない行では、ふつうにタブが入る")
    func notAList() {
        let textView = makeTextView("ふつうの段落")
        textView.insertTab(nil)
        #expect(textView.string.hasSuffix("\t"))
    }

    @Test("引用は深さを変えない")
    func quote() {
        let textView = makeTextView("> 引用")
        textView.insertTab(nil)
        #expect(textView.string.hasSuffix("\t"))
    }

    @Test("カーソルが行の途中でも、行頭のインデントが変わる")
    func caretInTheMiddle() {
        let textView = makeTextView("1. foo")
        textView.setSelectedRange(NSRange(location: 4, length: 0))
        textView.insertTab(nil)
        #expect(textView.string == "    1. foo")
    }

    @Test("これ以上戻せなければ、何も起きない")
    func nothingToRemove() {
        let textView = makeTextView("1. foo")
        textView.insertBacktab(nil)
        #expect(textView.string == "1. foo")
    }
}
#endif
