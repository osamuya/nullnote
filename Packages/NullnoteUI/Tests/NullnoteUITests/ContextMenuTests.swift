#if canImport(AppKit)
import AppKit
import Testing
@testable import NullnoteUI

/// 右クリックのメニューに、アプリ側の項目が足されるか。
///
/// **標準の項目（切り取り・コピー・ペースト）を作り直さない**ことも見る。
/// 作り直すと、OS の更新で増えた項目が落ちる。
@Suite("右クリックのメニュー")
@MainActor
struct ContextMenuTests {

    func makeTextView() -> FocusReportingTextView {
        let scrollView = NSTextView.scrollableTextView()
        let base = scrollView.documentView as! NSTextView
        return FocusReportingTextView(frame: base.frame, textContainer: base.textContainer!)
    }

    func rightClick(in textView: NSTextView) -> NSEvent {
        NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
            clickCount: 1, pressure: 1
        )!
    }

    @Test("足した項目がメニューの末尾に出る")
    func appended() {
        let textView = makeTextView()
        var called = false
        textView.extraContextMenuItems = [
            EditorContextMenuItem(title: "Finder で表示する", key: "r",
                                  modifiers: [.option, .command]) { called = true }
        ]
        let menu = textView.menu(for: rightClick(in: textView))
        let item = menu?.items.last
        #expect(item?.title == "Finder で表示する")
        #expect(item?.keyEquivalent == "r")
        #expect(item?.keyEquivalentModifierMask == [.option, .command])

        // 押すと処理が走る。
        _ = item.map { $0.target?.perform($0.action, with: $0) }
        #expect(called)
    }

    @Test("標準の項目は残っている")
    func standardItemsSurvive() {
        let textView = makeTextView()
        textView.string = "foo"
        let before = textView.menu(for: rightClick(in: textView))?.items.count ?? 0
        textView.extraContextMenuItems = [
            EditorContextMenuItem(title: "追加") {}
        ]
        let after = textView.menu(for: rightClick(in: textView))?.items.count ?? 0
        // 区切り線と項目のぶんだけ増える。標準は減っていない。
        #expect(after == before + 2)
    }

    @Test("足す項目が無ければ、標準のまま")
    func noExtras() {
        let textView = makeTextView()
        let menu = textView.menu(for: rightClick(in: textView))
        #expect(menu?.items.last?.isSeparatorItem != true)
    }
}
#endif
