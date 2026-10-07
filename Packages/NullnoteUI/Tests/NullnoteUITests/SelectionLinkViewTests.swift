#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
@testable import NullnoteUI

/// 編集画面とプレビューを並べて、選択が相手側の色になるところまで通す（#M0045）。
///
/// 選択の知らせは間引いてから出し、SwiftUI の更新を経て相手側に届く。
/// 決まり（`SelectionLinkTests`）と対応表（`SourceMapTests`）が正しくても、
/// この繋ぎが切れていれば何も起きないので、実物のビューで確かめる。
@Suite("選択の行き来（画面）")
@MainActor
struct SelectionLinkViewTests {

    static let source = "かつての**大雑把な**アクセス数というものを、GA4 では `_ga` で数えます。\n"

    private struct Harness: View {
        @State var link = SelectionLink()
        let text: String

        var body: some View {
            HStack(spacing: 0) {
                MarkdownEditorView(
                    text: .constant(text), theme: .standard(appearance: .light),
                    selectionMarks: link.editorMarks,
                    markReveal: link.editorReveal,
                    onSelectionChange: { ranges, line in link.editorSelectionChanged(ranges, line: line) }
                )
                MarkdownPreview(
                    source: text, theme: .standard(appearance: .light),
                    selectionMarks: link.previewMarks,
                    selectionReveal: link.previewReveal,
                    onSelectionChange: PreviewSelectionHandler { link.previewSelectionChanged($0) }
                )
            }
            .frame(width: 900, height: 300)
        }
    }

    private func makeWindow() async -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(text: Self.source))
        window.orderFront(nil)
        await spin()
        return window
    }

    /// 間引きの待ち（50ms）と SwiftUI の更新が済むまで待つ。
    ///
    /// **ランループを抱え込まない。** `RunLoop.main.run(until:)` で回すと、そのあいだ
    /// メインキューが止まり、並んで走るほかのテスト（ファイルの見張り）の知らせが届かなくなる。
    private func spin() async {
        try? await Task.sleep(for: .milliseconds(400))
    }

    /// 条件が揃うまで待つ。混んでいるときはビューの組み立ても知らせも遅れる。
    @discardableResult
    private func wait(until condition: () -> Bool) async -> Bool {
        for _ in 0..<60 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    /// 編集画面とプレビューのテキストビュー。組み上がるまで待つ。
    private func views(in window: NSWindow) async throws -> (FocusReportingTextView, LinkHoverTextView) {
        let root = try #require(window.contentView)
        await wait {
            !textViews(FocusReportingTextView.self, in: root).isEmpty
                && textViews(LinkHoverTextView.self, in: root).contains { !$0.string.isEmpty }
        }
        let editor = try #require(textViews(FocusReportingTextView.self, in: root).first)
        let preview = try #require(textViews(LinkHoverTextView.self, in: root).first { !$0.string.isEmpty })
        return (editor, preview)
    }

    private func textViews<T: NSTextView>(_ type: T.Type, in view: NSView) -> [T] {
        var found: [T] = []
        if let match = view as? T { found.append(match) }
        for child in view.subviews { found += textViews(type, in: child) }
        return found
    }

    private func isMarked(_ textView: NSTextView, at location: Int) -> Bool {
        textView.layoutManager?.temporaryAttribute(
            .backgroundColor, atCharacterIndex: location, effectiveRange: nil
        ) != nil
    }

    @Test("編集画面で選ぶとプレビューに色が付き、クリックすると消える")
    func editorToPreview() async throws {
        let window = await makeWindow()
        defer { window.close() }
        let (editor, preview) = try await views(in: window)

        window.makeFirstResponder(editor)
        editor.setSelectedRange((Self.source as NSString).range(of: "大雑把な"))

        let shown = preview.string as NSString
        #expect(await wait { isMarked(preview, at: shown.range(of: "大雑把な").location) })
        #expect(!isMarked(preview, at: shown.range(of: "かつて").location))

        // クリックしてカーソルだけになった。
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        #expect(await wait { !isMarked(preview, at: shown.range(of: "大雑把な").location) })
    }

    @Test("プレビューで選ぶと編集画面に色が付き、選択は動かない")
    func previewToEditor() async throws {
        let window = await makeWindow()
        defer { window.close() }
        let (editor, preview) = try await views(in: window)
        let caret = NSRange(location: 0, length: 0)
        editor.setSelectedRange(caret)

        window.makeFirstResponder(preview)
        preview.setSelectedRange((preview.string as NSString).range(of: "_ga"))

        let source = Self.source as NSString
        #expect(await wait { isMarked(editor, at: source.range(of: "_ga").location) })
        #expect(!isMarked(editor, at: source.range(of: "`_ga").location))
        #expect(editor.selectedRange() == caret)

        // プレビューをクリックして選択が無くなった。
        preview.setSelectedRange(NSRange(location: 1, length: 0))
        #expect(await wait { !isMarked(editor, at: source.range(of: "_ga").location) })
    }

    @Test("入力の焦点が無いときの選択の変化は、相手側に伝えない")
    func ignoresProgrammaticSelection() async throws {
        let window = await makeWindow()
        defer { window.close() }
        let (editor, preview) = try await views(in: window)

        window.makeFirstResponder(preview)
        editor.setSelectedRange((Self.source as NSString).range(of: "大雑把な"))
        await spin()
        #expect(!isMarked(preview, at: (preview.string as NSString).range(of: "大雑把な").location))
    }
    // MARK: - 位置だけがずれたとき

    @MainActor
    private final class Source: ObservableObject {
        @Published var text = "一つ目\n\n二つ目の段落\n"
        /// プレビューから知らされた本文の範囲。
        var reported: NSRange?
    }

    private struct PreviewHarness: View {
        @ObservedObject var source: Source
        var body: some View {
            MarkdownPreview(
                source: source.text, theme: .standard(appearance: .light),
                onSelectionChange: PreviewSelectionHandler { [source] in source.reported = $0 }
            )
            .frame(width: 600, height: 300)
        }
    }

    @Test("前に文字を足しても、後ろの段落は貼り直さず、本文の位置だけ替える")
    func positionsMoveWithoutRebuild() async throws {
        let source = Source()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: PreviewHarness(source: source))
        window.orderFront(nil)
        defer { window.close() }
        let root = try #require(window.contentView)

        func second() -> LinkHoverTextView? {
            textViews(LinkHoverTextView.self, in: root).first { $0.string.contains("二つ目") }
        }
        await wait { second() != nil }
        let view = try #require(second())
        let picked = (view.string as NSString).range(of: "段落")
        view.setSelectedRange(picked)

        source.text = "足した一つ目\n\n二つ目の段落\n"
        let moved = (source.text as NSString).range(of: "段落")
        // 組み直しは打鍵から 150ms 後（D-6）。済むまで待つ。
        await wait { textViews(LinkHoverTextView.self, in: root).contains { $0.string.contains("足した") } }
        try? await Task.sleep(for: .milliseconds(200))

        // 貼り直していれば、選択は外れている。
        #expect(view.selectedRange() == picked)

        // 選び直すと、新しい位置で知らされる。
        window.makeFirstResponder(view)
        view.setSelectedRange(NSRange(location: 0, length: 1))
        view.setSelectedRange(picked)
        #expect(await wait { source.reported == moved })
    }
}
#endif
