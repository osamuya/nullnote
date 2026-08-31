#if canImport(AppKit)
import AppKit
import MarkdownCore
import Testing
@testable import NullnoteUI

/// URL を打ち終えたときに `[URL](URL)` になるか。
///
/// 何を URL とみなすかの判断は `MarkdownCore` の `URLLinkify` にあり、
/// そちらでテストしてある。**ここで見るのは、区切りを打った瞬間の書き換え。**
@Suite("URL をリンクにする（エディタ側）")
@MainActor
struct URLLinkifyEditorTests {

    func makeTextView(_ text: String) -> FocusReportingTextView {
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    func makePasteboard(_ contents: String) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NullnoteTests.linkify"))
        pasteboard.clearContents()
        pasteboard.setString(contents, forType: .string)
        return pasteboard
    }

    @Test("空白を打つとリンクになる")
    func onSpace() {
        let textView = makeTextView("https://sabanote.com/apps/")
        textView.insertText(" ", replacementRange: textView.selectedRange())
        #expect(textView.string
                == "[https://sabanote.com/apps/](https://sabanote.com/apps/) ")
    }

    @Test("改行でもリンクになる")
    func onNewline() {
        let textView = makeTextView("https://sabanote.com/")
        textView.insertNewline(nil)
        #expect(textView.string == "[https://sabanote.com/](https://sabanote.com/)\n")
    }

    @Test("文の途中の URL でも、その部分だけが変わる")
    func inSentence() {
        let textView = makeTextView("詳しくは https://sabanote.com/")
        textView.insertText(" ", replacementRange: textView.selectedRange())
        #expect(textView.string == "詳しくは [https://sabanote.com/](https://sabanote.com/) ")
    }

    @Test("URL でなければ何も起きない")
    func notAURL() {
        let textView = makeTextView("ふつうの文章")
        textView.insertText(" ", replacementRange: textView.selectedRange())
        #expect(textView.string == "ふつうの文章 ")
    }

    @Test("すでにリンクの中なら二重にしない")
    func alreadyLinked() {
        let textView = makeTextView("[見出し](https://sabanote.com/")
        textView.insertText(" ", replacementRange: textView.selectedRange())
        #expect(textView.string == "[見出し](https://sabanote.com/ ")
    }

    @Test("URL だけを貼るとリンクになる")
    func paste() {
        let textView = makeTextView("")
        _ = textView.pasteAsLinkForTesting(from: makePasteboard("https://sabanote.com/apps/"))
        #expect(textView.string
                == "[https://sabanote.com/apps/](https://sabanote.com/apps/)")
    }

    /// 先に `[]()` を書いてから、括弧の中に URL を貼ると二重になっていた（実測）。
    @Test("括弧の中に貼ったときは、そのまま貼る")
    func pasteInsideParentheses() {
        let textView = makeTextView("[]()")
        textView.setSelectedRange(NSRange(location: 3, length: 0))   // `(` の直後
        let handled = textView.pasteAsLinkForTesting(
            from: makePasteboard("http://192.168.1.10:8080/")
        )
        #expect(!handled)
        #expect(textView.string == "[]()")
    }

    @Test("括弧の中で空白を打っても、リンクにしない")
    func typeInsideParentheses() {
        let textView = makeTextView("[](http://192.168.1.10:8080/")
        textView.insertText(" ", replacementRange: textView.selectedRange())
        #expect(textView.string == "[](http://192.168.1.10:8080/ ")
    }

    @Test("文章ごと貼ったときは触らない")
    func pasteSentence() {
        let textView = makeTextView("")
        let handled = textView.pasteAsLinkForTesting(
            from: makePasteboard("詳しくは https://sabanote.com/ を見てください")
        )
        #expect(!handled)
        #expect(textView.string == "")
    }

    @Test("取り消しで素の URL に戻る")
    func undo() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = "https://sabanote.com/"
        textView.allowsUndo = true
        scrollView.documentView = textView
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

        textView.insertText(" ", replacementRange: textView.selectedRange())
        #expect(textView.string.hasPrefix("[https://"))

        textView.breakUndoCoalescing()
        textView.undoManager?.undo()
        #expect(!textView.string.hasPrefix("[https://"))
    }
}
#endif
