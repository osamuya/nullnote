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
/// 目次から飛んだ行を光らせる表示。
///
/// 検索のハイライトと違い、**残さない**。1 秒ほど置いてから 5 秒かけて薄れる。
@Suite("ジャンプ先の点灯")
@MainActor
struct EditorFlashTests {

    let theme = MarkdownTheme.standard()

    func makeEditor(text: String) -> (NSTextView, MarkdownEditorView.Coordinator)? {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        guard let textView = scrollView.documentView as? NSTextView else { return nil }
        textView.string = text
        let coordinator = MarkdownEditorView.Coordinator(
            text: .constant(text), theme: theme, topVisibleLine: nil
        )
        coordinator.textView = textView
        coordinator.highlight(textView.textStorage, source: text)
        return (textView, coordinator)
    }

    func background(of textView: NSTextView, at location: Int) -> NSColor? {
        textView.textStorage?.attribute(.backgroundColor, at: location, effectiveRange: nil) as? NSColor
    }

    @Test("飛んだ行が光る")
    func lightsTheLine() throws {
        let made = try #require(makeEditor(text: "# 一行目\n\n## リンク\n\n本文\n"))
        let (textView, coordinator) = made

        #expect(background(of: textView, at: 0) == nil)
        coordinator.flash(line: 3)

        // 「## リンク」の行全体。記法文字も本文も塗られる。
        let line = try #require(coordinator.flashRange)
        #expect((textView.string as NSString).substring(with: line) == "## リンク")
        #expect(background(of: textView, at: line.location) != nil)
        #expect(background(of: textView, at: line.location + line.length - 1) != nil)
    }

    @Test("光らせる範囲に改行は含めない")
    func excludesNewline() throws {
        let made = try #require(makeEditor(text: "あ\nいう\nえ\n"))
        let (_, coordinator) = made

        coordinator.flash(line: 2)
        #expect(coordinator.flashRange == NSRange(location: 2, length: 2))
    }

    @Test("薄い色で塗る。文字色には触らない")
    func staysTranslucent() throws {
        // 不透明にすると見出しの文字が読めなくなる。地の色と混ぜて濃さを稼ぐ。
        let made = try #require(makeEditor(text: "## 見出し\n"))
        let (textView, coordinator) = made
        let headingColor = textView.textStorage?.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor

        coordinator.flash(line: 1)

        let painted = try #require(background(of: textView, at: 3))
        for appearance in [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua)] {
            appearance?.performAsCurrentDrawingAppearance {
                let alpha = painted.usingColorSpace(.sRGB)?.alphaComponent ?? 1
                #expect(alpha < 1)
                #expect(alpha > 0)
            }
        }
        // 文字色は見出しのまま。
        #expect((textView.textStorage?.attribute(.foregroundColor, at: 3, effectiveRange: nil) as? NSColor) === headingColor)
    }

    @Test("点灯の濃さは外観ごとに変える", arguments: [MarkdownAppearance.light, .dark])
    func alphaDependsOnAppearance(appearance: MarkdownAppearance) throws {
        // 黄色は明るいので、ダークで同じ濃さにすると白い文字とのコントラストが落ちる。
        let theme = MarkdownTheme.standard(appearance: appearance)
        let target = try #require(NSAppearance(named: appearance == .light ? .aqua : .darkAqua))

        var alpha = 0.0
        var contrast = 0.0
        target.performAsCurrentDrawingAppearance {
            let flash = theme.jumpFlash(progress: 1).usingColorSpace(.sRGB)
            alpha = Double(flash?.alphaComponent ?? 0)
            contrast = Self.contrast(theme.heading, Self.blend(flash, over: theme.background))
        }

        #expect(alpha == (appearance == .light ? 0.55 : 0.35))
        #expect(contrast >= 4.5, "点灯中に見出しが読めない: \\(contrast)")
    }

    @Test("薄れきると濃さが 0 になる")
    func fadesToNothing() throws {
        let theme = MarkdownTheme.standard(appearance: .dark)
        let target = try #require(NSAppearance(named: .darkAqua))
        target.performAsCurrentDrawingAppearance {
            #expect(theme.jumpFlash(progress: 0).usingColorSpace(.sRGB)?.alphaComponent == 0)
        }
    }

    /// 半透明の色を、地の色の上に重ねた結果。
    private static func blend(_ color: NSColor?, over background: NSColor) -> NSColor {
        guard let color = color?.usingColorSpace(.sRGB),
              let base = background.usingColorSpace(.sRGB)
        else { return background }
        let a = color.alphaComponent
        return NSColor(
            srgbRed: color.redComponent * a + base.redComponent * (1 - a),
            green: color.greenComponent * a + base.greenComponent * (1 - a),
            blue: color.blueComponent * a + base.blueComponent * (1 - a),
            alpha: 1
        )
    }

    /// WCAG のコントラスト比。
    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            guard let c = color.usingColorSpace(.sRGB) else { return 0 }
            func channel(_ v: Double) -> Double {
                v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(c.redComponent)
                + 0.7152 * channel(c.greenComponent)
                + 0.0722 * channel(c.blueComponent)
        }
        let high = max(luminance(a), luminance(b))
        let low = min(luminance(a), luminance(b))
        return (high + 0.05) / (low + 0.05)
    }

    @Test("打鍵で貼り直しても点灯は消えない")
    func survivesRehighlight() throws {
        let source = "## 見出し\n"
        let made = try #require(makeEditor(text: source))
        let (textView, coordinator) = made

        coordinator.flash(line: 1)
        // ハイライタは属性を捨ててから貼る。点灯がその後に載っていないと消える。
        coordinator.highlight(textView.textStorage, source: source)
        #expect(background(of: textView, at: 3) != nil)
    }

    @Test("空行を指されても塗らない")
    func ignoresEmptyLine() throws {
        let made = try #require(makeEditor(text: "あ\n\nい\n"))
        let (_, coordinator) = made

        coordinator.flash(line: 2)
        #expect(coordinator.flashRange == nil)
    }

    @Test("次のジャンプが来たら、そちらへ移る")
    func movesToNewLine() throws {
        let made = try #require(makeEditor(text: "# あ\n# い\n"))
        let (_, coordinator) = made

        coordinator.flash(line: 1)
        #expect(coordinator.flashRange?.location == 0)
        coordinator.flash(line: 2)
        #expect(coordinator.flashRange?.location == 4)
    }
}
#endif
