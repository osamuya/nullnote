#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

/// ⌘V が、選んだ**全箇所**に入るかどうか。
///
/// `NSTextView` の既定の貼り付けは、選んだところを全部消して先頭にだけ入れる（実測）。
/// 残りは消えたまま何も入らず、黙って中身が減る。ここを縛る。
///
/// 本物のクリップボード（`.general`）は使わない。確認のために利用者の手元を汚さない。
@Suite("複数選択への貼り付け")
@MainActor
struct MultiSelectionPasteTests {

    /// 本文を載せたテキストビュー。アプリで使っているものと同じ型。
    func makeTextView(_ text: String) -> FocusReportingTextView {
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        let textView = FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
        textView.string = text
        return textView
    }

    /// 確認専用のクリップボード。
    func makePasteboard(_ contents: String?) -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("NullnoteTests.paste"))
        pasteboard.clearContents()
        if let contents { pasteboard.setString(contents, forType: .string) }
        return pasteboard
    }

    func occurrences(of word: String, in text: String) -> [NSValue] {
        MultiSelection.allOccurrences(of: word, in: text).map { NSValue(range: $0) }
    }

    @Test("選んだ全箇所に入る")
    func pastesIntoEverySelection() {
        let text = "aaa parent bbb\nccc parent ddd\neee parent fff"
        let textView = makeTextView(text)
        textView.selectedRanges = occurrences(of: "parent", in: text)

        #expect(textView.pasteEverywhere(from: makePasteboard("child")))
        #expect(textView.string == "aaa child bbb\nccc child ddd\neee child fff")
    }

    @Test("貼ったあとも打ち込み先は全箇所に残る")
    func keepsTargetsAfterPaste() {
        let text = "aaa parent bbb\nccc parent ddd"
        let textView = makeTextView(text)
        textView.selectedRanges = occurrences(of: "parent", in: text)

        #expect(textView.pasteEverywhere(from: makePasteboard("child")))
        // 貼った直後に続けて打てる。長さ0の選択は AppKit がひとつにまとめてしまうので、
        // `selectedRanges` では確かめられない。打った結果で見る。
        textView.insertText("!", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(textView.string == "aaa child! bbb\nccc child! ddd")
    }

    @Test("複数行の中身は、分けずにそのまま各所へ入る")
    func multilineGoesInWhole() {
        // 貼り付けは「入れたものがそのまま入る」道具。行が増えるのはカーソル1つでも同じ。
        let text = "a X b\nc X d"
        let textView = makeTextView(text)
        textView.selectedRanges = occurrences(of: "X", in: text)

        #expect(textView.pasteEverywhere(from: makePasteboard("1\n2")))
        #expect(textView.string == "a 1\n2 b\nc 1\n2 d")
    }

    @Test("消したあとのカーソルにも入る")
    func pastesIntoCaretsLeftByDeleting() {
        // 長さ0の選択は AppKit がひとつにまとめてしまうので、行き先は自前で持っている。
        let text = "aaa parent bbb\nccc parent ddd"
        let textView = makeTextView(text)
        textView.selectedRanges = occurrences(of: "parent", in: text)
        textView.deleteBackward(nil)

        #expect(textView.pasteEverywhere(from: makePasteboard("child")))
        #expect(textView.string == "aaa child bbb\nccc child ddd")
    }

    @Test("ひとつしか選んでいなければ引き受けない")
    func declinesSingleSelection() {
        // 既定の貼り付けに任せる。取り消しも書式も AppKit の作法のまま。
        let textView = makeTextView("aaa parent bbb")
        textView.setSelectedRange(NSRange(location: 4, length: 6))

        #expect(textView.pasteEverywhere(from: makePasteboard("child")) == false)
        #expect(textView.string == "aaa parent bbb")
    }

    @Test("文字が取れなければ引き受けない")
    func declinesEmptyPasteboard() {
        // 画像だけが入っている場合など。消してから何も入らない、が一番まずい。
        let text = "aaa parent bbb\nccc parent ddd"
        let textView = makeTextView(text)
        textView.selectedRanges = occurrences(of: "parent", in: text)

        #expect(textView.pasteEverywhere(from: makePasteboard(nil)) == false)
        #expect(textView.string == text)
    }
}
#endif
