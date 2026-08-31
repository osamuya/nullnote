#if canImport(AppKit)
import AppKit
import MarkdownCore
import Testing
@testable import NullnoteUI

/// Return を押したときに、本文がどう変わるか。
///
/// 何を継ぐかの判断は `MarkdownCore` の `LineContinuationRule` にあり、
/// そちらでテストしてある。**ここで見るのは、判断どおりに本文が書き換わるか**と、
/// コードブロックの中では継がないという繋ぎ込みの部分。
@Suite("改行で行頭の印を継ぐ（エディタ側）")
@MainActor
struct LineContinuationEditorTests {

    func makeTextView(_ text: String, caretAtEnd: Bool = true) -> FocusReportingTextView {
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = text
        if caretAtEnd {
            textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        }
        return textView
    }

    @Test("箇条書きの行で改行すると、次の行に印が入る")
    func bullet() {
        let textView = makeTextView("- りんご")
        textView.insertNewline(nil)
        #expect(textView.string == "- りんご\n- ")
    }

    @Test("順序つきは 1. で継ぐ")
    func ordered() {
        let textView = makeTextView("3. さんばんめ")
        textView.insertNewline(nil)
        #expect(textView.string == "3. さんばんめ\n1. ")
    }

    @Test("インデントも継ぐ")
    func indent() {
        let textView = makeTextView("  - 入れ子")
        textView.insertNewline(nil)
        #expect(textView.string == "  - 入れ子\n  - ")
    }

    @Test("印だけの行で改行すると、印が消えて空行になる")
    func endList() {
        let textView = makeTextView("- りんご\n- ")
        textView.insertNewline(nil)
        #expect(textView.string == "- りんご\n\n")
    }

    @Test("引用の行で改行すると、次の行にも `> ` が入る")
    func quote() {
        let textView = makeTextView("> 引用")
        textView.insertNewline(nil)
        #expect(textView.string == "> 引用\n> ")
    }

    @Test("引用の中のリストは、両方継ぐ")
    func quotedList() {
        let textView = makeTextView("> - りんご")
        textView.insertNewline(nil)
        #expect(textView.string == "> - りんご\n> - ")
    }

    @Test("引用の印だけの行で改行すると、抜ける")
    func endQuote() {
        let textView = makeTextView("> 引用\n> ")
        textView.insertNewline(nil)
        #expect(textView.string == "> 引用\n\n")
    }

    @Test("リストでない行は、ふつうに改行する")
    func plain() {
        let textView = makeTextView("ふつうの段落")
        textView.insertNewline(nil)
        #expect(textView.string == "ふつうの段落\n")
    }

    @Test("本文の途中で改行すると、後半にも印が付く")
    func splitInTheMiddle() {
        let textView = makeTextView("- りんごとみかん", caretAtEnd: false)
        textView.setSelectedRange(NSRange(location: 5, length: 0))   // 「ご」の後ろ
        textView.insertNewline(nil)
        #expect(textView.string == "- りんご\n- とみかん")
    }

    @Test("選択範囲があるときは、ふつうの改行に任せる")
    func withSelection() {
        let textView = makeTextView("- りんご", caretAtEnd: false)
        textView.setSelectedRange(NSRange(location: 2, length: 3))   // 「りんご」
        textView.insertNewline(nil)
        #expect(textView.string == "- \n")
    }

    @Test("コードブロックの中では継がない")
    func insideCode() {
        let textView = makeTextView("- rf")
        // 「この行の手前はフェンスの中」と答えさせる。
        textView.lineNumber = { _ in 1 }
        textView.blockStateBeforeLine = { _ in .fencedCode(marker: .backtick, length: 3) }
        textView.insertNewline(nil)
        #expect(textView.string == "- rf\n")
    }

    @Test("繋がっていなければ、コードの中ではないとみなす")
    func withoutWiring() {
        let textView = makeTextView("- りんご")
        textView.lineNumber = nil
        textView.blockStateBeforeLine = nil
        textView.insertNewline(nil)
        #expect(textView.string == "- りんご\n- ")
    }

    /// 取り消しは `undoManager` がウインドウから降りてくる。
    /// **載せていないと nil になり、`undo()` が黙って何もしない。**
    @Test("取り消しで元に戻る")
    func undo() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = "- りんご"
        textView.allowsUndo = true
        scrollView.documentView = textView
        window.contentView = scrollView
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))

        textView.insertNewline(nil)
        #expect(textView.string == "- りんご\n- ")

        textView.breakUndoCoalescing()
        #expect(textView.undoManager != nil)
        textView.undoManager?.undo()
        #expect(textView.string == "- りんご")
    }
}
#endif
