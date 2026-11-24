#if canImport(AppKit)
import AppKit
import MarkdownCore
import Testing
@testable import NullnoteUI

/// Return で行末に半角スペース2つを入れる（#015・D-79）。
///
/// 入れるかどうかの判断は `MarkdownCore` の `HardBreakRule` でテストしてある。
/// **ここで見るのは、設定どおりに本文が書き換わるか**と、取り消しが1回で済むか。
@Suite("改行で行末に空白2つを入れる（エディタ側）")
@MainActor
struct HardBreakEditorTests {

    func makeTextView(_ text: String, caret: Int? = nil, enabled: Bool = true) -> FocusReportingTextView {
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = text
        textView.addsHardBreakOnNewline = enabled
        textView.setSelectedRange(NSRange(location: caret ?? (text as NSString).length, length: 0))
        return textView
    }

    @Test("入れてあると、普通の行の改行で行末に空白2つが入る")
    func plainLine() {
        let textView = makeTextView("一行目")
        textView.insertNewline(nil)
        #expect(textView.string == "一行目  \n")
        #expect(textView.selectedRange() == NSRange(location: 6, length: 0))
    }

    @Test("切ってあれば、今までどおり改行だけ")
    func disabled() {
        let textView = makeTextView("一行目", enabled: false)
        textView.insertNewline(nil)
        #expect(textView.string == "一行目\n")
    }

    @Test("行の途中で押すと、前半の末尾に入る")
    func middle() {
        let textView = makeTextView("前半後半", caret: 2)
        textView.insertNewline(nil)
        #expect(textView.string == "前半  \n後半")
    }

    @Test("引用の行では、空白2つを入れてから `> ` を継ぐ")
    func quote() {
        let textView = makeTextView("> 引用")
        textView.insertNewline(nil)
        #expect(textView.string == "> 引用  \n> ")
    }

    @Test("リストの行には入れない")
    func list() {
        let textView = makeTextView("- りんご")
        textView.insertNewline(nil)
        #expect(textView.string == "- りんご\n- ")
    }

    @Test("空行を作る改行には入れない")
    func blankLine() {
        let textView = makeTextView("一行目  \n")
        textView.insertNewline(nil)
        #expect(textView.string == "一行目  \n\n")
    }

    @Test("取り消し1回で、改行と空白がまとめて戻る")
    func undo() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = "一行目"
        textView.allowsUndo = true
        textView.addsHardBreakOnNewline = true
        scrollView.documentView = textView
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        textView.insertNewline(nil)
        #expect(textView.string == "一行目  \n")

        textView.breakUndoCoalescing()
        textView.undoManager?.undo()
        #expect(textView.string == "一行目")
    }
}
#endif
