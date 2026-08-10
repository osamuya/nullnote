#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

/// 検索のヒットが、エディタの本文に実際に塗られるかどうか。
///
/// ハイライタは属性を**貼り直す**（既存を捨てる）ので、検索の色は必ずその後に載せる。
/// 順序を取り違えると、コードブロックの中だけ色が付かないといった形で出る。
@Suite("エディタの検索ハイライト")
@MainActor
struct EditorSearchHighlightTests {

    let theme = MarkdownTheme.standard()

    func paint(_ source: String, highlight: SearchHighlight?) -> NSTextStorage {
        let coordinator = MarkdownEditorView.Coordinator(
            text: .constant(source), theme: theme, topVisibleLine: nil
        )
        coordinator.searchHighlight = highlight
        let storage = NSTextStorage(string: source)
        coordinator.highlight(storage, source: source)
        return storage
    }

    func background(of storage: NSTextStorage, at location: Int) -> NSColor? {
        storage.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    @Test("ヒットした語に背景が付く")
    func paintsMatches() {
        let source = "検索と検索"
        let matches = DocumentSearch.matches(of: "検索", in: source)
        let storage = paint(source, highlight: SearchHighlight(matches: matches, current: 0))

        #expect(background(of: storage, at: 0) === theme.searchCurrentMatch)
        #expect(background(of: storage, at: 3) === theme.searchMatch)
        // ヒットの外は塗らない。
        #expect(background(of: storage, at: 2) == nil)
    }

    @Test("いま見ているヒットだけ色が違う")
    func currentMatchDiffers() {
        let source = "a a a"
        let matches = DocumentSearch.matches(of: "a", in: source)
        let storage = paint(source, highlight: SearchHighlight(matches: matches, current: 1))

        #expect(background(of: storage, at: 0) === theme.searchMatch)
        #expect(background(of: storage, at: 2) === theme.searchCurrentMatch)
        #expect(background(of: storage, at: 4) === theme.searchMatch)
    }

    @Test("コードブロックの中でも検索の色が勝つ")
    func winsOverCodeBackground() throws {
        let source = "```swift\nlet target = 1\n```\n"
        let matches = DocumentSearch.matches(of: "target", in: source)
        let hit = try #require(matches.first)

        // 検索していないときは、コードブロックの背景で塗られている。
        let plain = paint(source, highlight: nil)
        #expect(background(of: plain, at: hit.location) === theme.codeBackground)

        // 検索するとヒットの範囲だけ上書きされる。
        let searched = paint(source, highlight: SearchHighlight(matches: matches, current: 0))
        #expect(background(of: searched, at: hit.location) === theme.searchCurrentMatch)
        // ヒットの外はコードブロックの背景のまま。
        #expect(background(of: searched, at: 9) === theme.codeBackground)
    }

    @Test("ヒットの上の文字はヒット用の色に差し替わる")
    func replacesForegroundColor() {
        // 見出しの色や構文の色のまま背景だけ変えると、読めない組み合わせが出る。
        let source = "# 見出しの中の語\n"
        let matches = DocumentSearch.matches(of: "見出し", in: source)
        let storage = paint(source, highlight: SearchHighlight(matches: matches, current: 0))
        let color = storage.attribute(.foregroundColor, at: 2, effectiveRange: nil) as? NSColor

        #expect(color === theme.searchMatchText)
    }

    @Test("ヒットの文字色は外観で変わらない")
    func matchTextIgnoresAppearance() throws {
        // ライトとダークで同じ暗い色。ここを追従させると、ダークで白い文字を
        // 載せることになり、背景の側を濁らせるほかなくなる。
        let light = try #require(MarkdownTheme.standard(appearance: .light).searchMatchText
            .usingColorSpace(.sRGB))
        let dark = try #require(MarkdownTheme.standard(appearance: .dark).searchMatchText
            .usingColorSpace(.sRGB))
        #expect(light == dark)
    }

    @Test("検索していなければ何も塗られない")
    func noHighlight() {
        let storage = paint("ふつうの本文", highlight: nil)
        #expect(background(of: storage, at: 0) == nil)
    }

    @Test("本文より後ろを指す範囲は飛ばす")
    func ignoresOutOfBounds() {
        // 本文の更新とヒットの数え直しが1周期ずれると、古い範囲が届くことがある。
        let source = "みじかい"
        let stale = SearchHighlight(matches: [NSRange(location: 100, length: 5)], current: 0)
        let storage = paint(source, highlight: stale)
        #expect(storage.length == (source as NSString).length)
        #expect(background(of: storage, at: 0) == nil)
    }
}

/// 前後へ送ったときに、そのヒットが見えるところに来るか。
@Suite("検索したヒットへの移動")
@MainActor
struct EditorSearchSelectionTests {

    /// 200pt の高さに 300 行を載せる。目的のヒットは必ず画面の外から始まる。
    func makeEditor(text: String) -> (NSScrollView, NSTextView, MarkdownEditorView.Coordinator)? {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        guard let textView = scrollView.documentView as? NSTextView else { return nil }
        textView.textContainerInset = .zero
        textView.string = text
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        scrollView.layoutSubtreeIfNeeded()

        let coordinator = MarkdownEditorView.Coordinator(
            text: .constant(text), theme: .standard(), topVisibleLine: nil
        )
        coordinator.textView = textView
        return (scrollView, textView, coordinator)
    }

    @Test("下の方のヒットへ送るとスクロールし、先頭にカーソルが立つ")
    func scrollsToMatch() throws {
        let text = (1...300).map { $0 == 250 ? "目印" : "line \($0)" }.joined(separator: "\n")
        let made = try #require(makeEditor(text: text))
        let (scrollView, textView, coordinator) = made
        let match = try #require(DocumentSearch.matches(of: "目印", in: text).first)

        #expect(scrollView.contentView.bounds.origin.y == 0)
        coordinator.reveal(match)
        scrollView.layoutSubtreeIfNeeded()

        #expect(textView.selectedRange() == NSRange(location: match.location, length: 0))
        #expect(scrollView.contentView.bounds.origin.y > 0)
    }

    @Test("ヒットは画面の上端ではなく中ほどに来る")
    func centersMatch() throws {
        let text = (1...300).map { $0 == 250 ? "目印" : "line \($0)" }.joined(separator: "\n")
        let made = try #require(makeEditor(text: text))
        let (scrollView, textView, coordinator) = made
        let match = try #require(DocumentSearch.matches(of: "目印", in: text).first)

        coordinator.reveal(match)
        scrollView.layoutSubtreeIfNeeded()

        let layoutManager = try #require(textView.layoutManager)
        let container = try #require(textView.textContainer)
        let glyphs = layoutManager.glyphRange(forCharacterRange: match, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
        let visible = scrollView.contentView.bounds

        // 上端合わせなら 0 に近い値になる。中ほどに置いているので、
        // ヒットの位置は表示範囲の中央あたりに来る。
        let offsetInView = rect.midY - visible.origin.y
        #expect(offsetInView > visible.height * 0.3)
        #expect(offsetInView < visible.height * 0.7)
    }

    @Test("範囲は選択しない。選択の灰色がヒットの色を覆うため")
    func doesNotSelectTheRange() throws {
        // 検索欄に入力の焦点があるあいだ、テキストビューは非アクティブ。
        // AppKit は選択範囲を `unemphasizedSelectedTextBackgroundColor`（灰色）で
        // 塗り、しかもそれは属性の背景色より後に描かれる。
        // 範囲を選ぶと、いま見ているヒットが灰色に見えてしまう。
        let text = "目印のある本文"
        let made = try #require(makeEditor(text: text))
        let (_, textView, coordinator) = made
        let match = try #require(DocumentSearch.matches(of: "目印", in: text).first)

        #expect(match.length > 0)
        coordinator.reveal(match)
        #expect(textView.selectedRange().length == 0)
    }

    @Test("本文より後ろを指されても落ちない")
    func clampsOutOfBounds() throws {
        let made = try #require(makeEditor(text: "みじかい本文"))
        let (_, textView, coordinator) = made

        coordinator.reveal(NSRange(location: 100, length: 20))
        let selection = textView.selectedRange()
        #expect(selection.location + selection.length <= (textView.string as NSString).length)
    }
}
#endif
