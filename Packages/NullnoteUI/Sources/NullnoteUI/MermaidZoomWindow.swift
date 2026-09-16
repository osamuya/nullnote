#if canImport(AppKit)
import AppKit
import SwiftUI
import WebKit

/// 図を大きく見るための窓（D-65 の続き）。
///
/// **焼いた画像は置かない。** プレビューに埋めたものと同じ `host.html` を、
/// もう一枚の `WKWebView` に読ませる。SVG が生きたままなので、
/// **何倍に拡大しても字は潰れず、文字は選べる**（実測：3倍で 619 文字、原寸と同じ）。
///
/// 窓は1枚だけ使い回す。`ImageZoomWindow` と同じ作法。
/// **閉じたら中身を捨てる。** WebView を抱えたままにすると、見ていないあいだも
/// WebKit のプロセス（実測でおよそ 240 MB）を持ち続ける。
@MainActor
final class MermaidZoomWindow {

    static let shared = MermaidZoomWindow()

    private var window: NSWindow?

    private init() {}

    func show(code: String, theme: MarkdownTheme) {
        let controller = DiagramZoomController()
        let content = ZoomedDiagramView(
            code: code,
            theme: theme,
            controller: controller,
            onClose: { [weak self] in self?.close() }
        )

        let window = self.window ?? makeWindow()
        window.contentView = NSHostingView(rootView: content)
        window.appearance = theme.appearance.platformAppearance
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private func close() {
        window?.orderOut(nil)
        // **中身を捨てる。** WebView が外れて、WebKit のプロセスが片付く。
        window?.contentView = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = String(localized: "図", bundle: .module)
        window.center()
        window.collectionBehavior.insert(.fullScreenPrimary)
        return window
    }
}

// MARK: - 窓の中身

private struct ZoomedDiagramView: View {

    let code: String
    let theme: MarkdownTheme
    @ObservedObject var controller: DiagramZoomController
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DiagramZoomWebView(
                code: code,
                theme: theme.appearance.resolvedColorScheme == .dark ? "dark" : "default",
                errorMessage: String(localized: "この図は描けません", bundle: .module),
                textColor: theme.text,
                background: theme.codeBackground,
                controller: controller
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            controls
        }
        .frame(minWidth: 400, minHeight: 300)
        .background(Color(platform: theme.background))
        .markdownColorScheme(theme.appearance)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            step(systemImage: "minus.magnifyingglass", help: Text("縮小", bundle: .module)) {
                controller.zoom(by: 1 / 1.25)
            }
            // 倍率は幅を固定する。数字が変わるたびにボタンが動くと押しにくい。
            Text(verbatim: "\(Int((controller.scale * 100).rounded()))%")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(Color(platform: theme.quote))
                .frame(width: 48)
            step(systemImage: "plus.magnifyingglass", help: Text("拡大", bundle: .module)) {
                controller.zoom(by: 1.25)
            }

            Divider().frame(height: 16)

            Button(String(localized: "全体を見る", bundle: .module)) { controller.fit() }
                .keyboardShortcut("0", modifiers: .command)
            Button(String(localized: "等倍", bundle: .module)) { controller.actualSize() }
                .keyboardShortcut("1", modifiers: .command)

            Spacer()

            // 操作の案内。**覚えさせない。**見えているところに書いておく。
            Text("ドラッグか二本指で移動。ピンチ、⌘＋ホイールで拡大", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(Color(platform: theme.quote))
                .lineLimit(1)

            Button(String(localized: "閉じる", bundle: .module)) { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func step(systemImage: String, help: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(platform: theme.marker))
        .help(help)
    }
}

// MARK: - 倍率の操作

/// ボタンから WebView の中の倍率を動かす。
@MainActor
final class DiagramZoomController: ObservableObject {

    /// いまの倍率。頁の側が変えたら、こちらへ返ってくる。
    @Published private(set) var scale: Double = 1

    fileprivate weak var webView: WKWebView?

    func zoom(by factor: Double) {
        call("return zoomBy(factor);", ["factor": factor])
    }

    func fit() { call("return fitToWindow();", [:]) }

    func actualSize() { call("return actualSize();", [:]) }

    fileprivate func noteScale(_ value: Double) { scale = value }

    private func call(_ script: String, _ arguments: [String: Any]) {
        webView?.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            if case let .success(value) = result, let next = value as? Double {
                self?.noteScale(next)
            }
        }
    }
}

// MARK: - WebView

private struct DiagramZoomWebView: NSViewRepresentable {

    let code: String
    let theme: String
    let errorMessage: String
    let textColor: PlatformColor
    let background: PlatformColor
    let controller: DiagramZoomController

    func makeCoordinator() -> Coordinator {
        Coordinator(
            code: code, theme: theme, errorMessage: errorMessage,
            textColor: textColor, background: background, controller: controller
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = MermaidCoordinator.makeWebView(delegate: context.coordinator)
        // 拡大窓は自分の地の色を敷く。透かすと、拡大して隙間が出たときに
        // 後ろの窓が見える。
        view.setValue(true, forKey: "drawsBackground")
        controller.webView = view
        guard let host = MermaidCoordinator.hostURL else { return view }
        view.loadFileURL(host, allowingReadAccessTo: host.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    /// 器の読み込みが終わってから、拡大窓として仕立てる。
    @MainActor
    final class Coordinator: MermaidCoordinator {

        private let controller: DiagramZoomController

        init(
            code: String, theme: String, errorMessage: String,
            textColor: PlatformColor, background: PlatformColor,
            controller: DiagramZoomController
        ) {
            self.controller = controller
            super.init(
                code: code, theme: theme, errorMessage: errorMessage,
                textColor: textColor, background: background,
                height: .constant(0), isReady: .constant(false)
            )
        }

        override func draw(in webView: WKWebView) {
            webView.callAsyncJavaScript(
                "return await setUpZoom(code, theme);",
                arguments: ["code": code, "theme": theme],
                in: nil, in: .page
            ) { [weak self] result in
                guard let self else { return }
                if case let .success(value) = result,
                   let dictionary = value as? [String: Any],
                   dictionary["ok"] as? Bool == true {
                    self.readBackScale(from: webView)
                    return
                }
                self.showError(in: webView)
            }
        }

        private func readBackScale(from webView: WKWebView) {
            webView.callAsyncJavaScript(
                "return currentScale();", arguments: [:], in: nil, in: .page
            ) { [weak self] result in
                if case let .success(value) = result, let scale = value as? Double {
                    self?.controller.noteScale(scale)
                }
            }
        }
    }
}
#endif
