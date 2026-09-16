#if canImport(AppKit)
import AppKit
import Testing
import WebKit
@testable import NullnoteUI

@Suite("図の上でのスクロール")
@MainActor
struct MermaidScrollThroughTests {

    /// ホイールを受け取ったかを覚えるだけのビュー。図の親役。
    final class Recorder: NSView {
        var received = 0
        override func scrollWheel(with event: NSEvent) { received += 1 }
    }

    /// 本物のホイールのイベントを1つ作る。
    func wheelEvent() -> NSEvent? {
        guard let cg = CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: -10, wheel2: 0, wheel3: 0
        ) else { return nil }
        return NSEvent(cgEvent: cg)
    }

    @Test("埋め込んだ図は、ホイールを外へ渡す")
    func embeddedPassesThrough() throws {
        // **これが無いと、図の上でホイールを回してもプレビューが動かない。**
        // 実機で「図の外では末尾まで送れるのに、図の上では途中で止まる」
        // という形で出た（2026-09-16）。頁の CSS を overflow: hidden に
        // しても止まらず、ビューの側で渡すしかなかった。
        let parent = Recorder(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let webView = ScrollThroughWebView(
            frame: .init(x: 0, y: 0, width: 400, height: 300),
            configuration: WKWebViewConfiguration()
        )
        parent.addSubview(webView)

        let event = try #require(wheelEvent(), "ホイールのイベントを作れない")
        webView.scrollWheel(with: event)

        #expect(parent.received == 1, "図がホイールを握ったまま外へ渡していない")
    }

    @Test("素の WKWebView は、ホイールを外へ渡さない")
    func plainWebViewKeepsIt() throws {
        // 上のテストが「たまたま通っている」のではないことを示す。
        // 素のままだと渡らない、という前提が崩れたらここが落ちる。
        let parent = Recorder(frame: .init(x: 0, y: 0, width: 400, height: 300))
        let webView = WKWebView(
            frame: .init(x: 0, y: 0, width: 400, height: 300),
            configuration: WKWebViewConfiguration()
        )
        parent.addSubview(webView)

        let event = try #require(wheelEvent(), "ホイールのイベントを作れない")
        webView.scrollWheel(with: event)

        #expect(parent.received == 0)
    }

    @Test("拡大窓の図は、素通しにしない")
    func zoomWindowKeepsItsOwnScrolling() {
        // 拡大窓は自分の中でスクロールして図を動かす。
        // ここを素通しにすると、拡大窓で移動できなくなる。
        let embedded = MermaidCoordinator.makeWebView(
            delegate: makeCoordinator(), passesScrollThrough: true
        )
        let zoom = MermaidCoordinator.makeWebView(
            delegate: makeCoordinator(), passesScrollThrough: false
        )
        #expect(embedded is ScrollThroughWebView)
        #expect(!(zoom is ScrollThroughWebView))
    }

    private func makeCoordinator() -> MermaidCoordinator {
        MermaidCoordinator(
            code: "graph TD\n A-->B", theme: "default", errorMessage: "",
            textColor: .textColor, background: .textBackgroundColor,
            height: .constant(0), isReady: .constant(false)
        )
    }
}
#endif
