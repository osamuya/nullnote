#if canImport(AppKit)
import AppKit
import SwiftUI

/// 画像を大きく見るための窓。
///
/// **シートにしない。** シートは利用者が大きさを変えられず、大きな絵を見るのに向かない。
/// 窓なら広げられるし、全画面にもできる。
///
/// 窓は1枚だけ使い回す。押すたびに増えると、閉じて回るのが手間になる。
@MainActor
final class ImageZoomWindow {

    static let shared = ImageZoomWindow()

    private var window: NSWindow?

    private init() {}

    func show(
        images: [PreviewImageRef],
        startAt index: Int,
        theme: MarkdownTheme,
        documentURL: URL?
    ) {
        guard !images.isEmpty else { return }

        let content = ZoomedImageContainer(
            images: images, startIndex: index, theme: theme, documentURL: documentURL,
            onClose: { [weak self] in self?.close() }
        )
        let hosting = NSHostingView(rootView: content)

        let window = self.window ?? makeWindow()
        window.contentView = hosting
        window.title = images[min(max(index, 0), images.count - 1)].alt
        window.appearance = theme.appearance.platformAppearance
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: false)
    }

    private func close() {
        window?.orderOut(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        // 閉じても捨てない。使い回す。
        window.isReleasedWhenClosed = false
        window.center()
        window.collectionBehavior.insert(.fullScreenPrimary)
        return window
    }
}

/// 窓の中身。**位置を自分で持つ。**
/// 窓の側に状態を持たせると、送るたびに窓を作り直すことになる。
private struct ZoomedImageContainer: View {

    let images: [PreviewImageRef]
    let startIndex: Int
    let theme: MarkdownTheme
    let documentURL: URL?
    let onClose: () -> Void

    @State private var index: Int = 0

    var body: some View {
        ZoomedImageView(
            images: images, index: $index, theme: theme,
            documentURL: documentURL, onClose: onClose
        )
        .onAppear { index = min(max(startIndex, 0), images.count - 1) }
    }
}
#endif
