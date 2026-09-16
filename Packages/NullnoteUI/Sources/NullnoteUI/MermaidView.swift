import SwiftUI
import WebKit

// ```mermaid の図を、プレビューの中に埋めた WKWebView で描く（D-65 の A 案）。
//
// **図1つにつき WebView が1つ立つ。** 安くはない。実測（2026-09-16、macOS 26.6.2）で
// 図8個のとき WebKit のプロセスが10個、合わせて 1.3 GB だった。図1個なら 317 MB で、
// 焼いて画像にする案（B 案）の 297 MB とほとんど変わらない。
// **分かれ目は図の数**で、1つの文書に図がいくつも並ぶと差が開く。
//
// それでも A 案を採ったのは、**図の中の文字を選んでコピーできる**ため。
// mermaid はラベルを `<foreignObject>` の中の XHTML として持つので、
// WebView の中なら選べる（実測で 619 文字取れた）。焼いて画像にすると、そこが消える。
// 判断の記録は `docs/02-decision-log.md` の D-65。
//
// **選択は図の中で閉じる。** 上の段落から図をまたいで下の段落まで、
// 一続きにドラッグして選ぶことはできない。WebView が自分の選択を持つため。
//
// 同梱している mermaid の版と入れ替えかたは `docs/13-mermaid.md`。

/// プレビューに置く mermaid の図。
///
/// 高さは描いてみるまで分からない。描き終わってから枠を広げるので、
/// **出たあとに一度だけ高さが変わる。**
struct MermaidBlockView: View {

    let code: String
    let theme: MarkdownTheme

    /// 描く前の高さ。**0 にしない。** 0 だと枠が畳まれて WebView が版組みを始めず、
    /// いつまでも描かれない。本文1行ぶんだけ空けておく。
    private static let placeholderHeight: CGFloat = 24

    /// 図が高さを決めたことをプレビューへ伝える口。
    /// **これを呼ばないと、図より下へスクロール同期が届かない。**
    @Environment(\.onDiagramRendered) private var onRendered

    @State private var height: CGFloat = MermaidBlockView.placeholderHeight
    @State private var isReady = false
    @State private var isHovering = false

    var body: some View {
        diagram
            #if canImport(AppKit)
            // **図そのものを押して開く形にしない。** 図の中の文字はドラッグで
            // 選べるので、押して開くようにすると選ぼうとするたびに窓が出る。
            // 角の小さな札に寄せて、選択と両立させる（画像の作法とは変えている）。
            .overlay(alignment: .topTrailing) { enlargeButton }
            .onHover { isHovering = $0 }
            #endif
            .onChange(of: height) { _, _ in onRendered() }
    }

    private var diagram: some View {
        MermaidWebView(
            code: code,
            theme: mermaidTheme,
            errorMessage: String(localized: "この図は描けません", bundle: .module),
            textColor: theme.text,
            background: theme.codeBackground,
            height: $height,
            isReady: $isReady
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 描き終わるまでは器を見せない。高さが決まる前の枠が、
        // 空のコードブロックのように見えてしまう。
        .opacity(isReady ? 1 : 0)
        // **図の中身とテーマが変われば作り直す。** 同じ WebView を使い回して
        // 描き直すこともできるが、打鍵のたびに走らせる価値はない。
        // 解析自体が入力停止から 150ms 待つので、ここまで来る回数は多くない。
        .id(MermaidIdentity(code: code, theme: mermaidTheme))
    }

    #if canImport(AppKit)
    /// 大きく見るための札。**指を乗せたときだけ出す。**
    /// 常に出していると、小さな図では図そのものに重なる。
    @ViewBuilder private var enlargeButton: some View {
        if isReady && isHovering {
            Button {
                MermaidZoomWindow.shared.show(code: code, theme: theme)
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color(platform: theme.codeBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color(platform: theme.marker).opacity(0.4), lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(platform: theme.marker))
            .help(Text("図を大きく見る", bundle: .module))
            .padding(6)
        }
    }
    #endif

    /// mermaid に渡すテーマの名前。**`.system` を素通ししない。**
    /// mermaid は OS の外観を知らないので、こちら側で解いてから渡す。
    @MainActor private var mermaidTheme: String {
        theme.appearance.resolvedColorScheme == .dark ? "dark" : "default"
    }
}

/// 作り直しの判断に使う組。
private struct MermaidIdentity: Hashable {
    let code: String
    let theme: String
}

// MARK: - WebView

#if canImport(AppKit)
import AppKit

struct MermaidWebView: NSViewRepresentable {

    let code: String
    let theme: String
    let errorMessage: String
    let textColor: PlatformColor
    let background: PlatformColor
    @Binding var height: CGFloat
    @Binding var isReady: Bool

    func makeCoordinator() -> MermaidCoordinator {
        MermaidCoordinator(
            code: code, theme: theme, errorMessage: errorMessage,
            textColor: textColor, background: background,
            height: $height, isReady: $isReady
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let view = MermaidCoordinator.makeWebView(
            delegate: context.coordinator, passesScrollThrough: true
        )
        context.coordinator.load(into: view)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// ホイールを自分で握らず、外のスクロールへ渡す `WKWebView`。
///
/// **これが無いと、図の上でホイールを回してもプレビューが動かない。**
/// `WKWebView` は、頁がスクロールできない場合でもホイールを自分で処理し、
/// 外へ渡さない。頁の CSS を `overflow: hidden` にしても止まらないことを
/// 実機で確かめてある（2026-09-16。図の外では末尾まで送れるのに、
/// 図の上では途中で止まる、という形で出た）。
///
/// **埋め込んだ図だけに使う。** 拡大窓は自分でスクロールするので、
/// ここで素通しさせると動かなくなる。
final class ScrollThroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }
}

#elseif canImport(UIKit)
import UIKit

struct MermaidWebView: UIViewRepresentable {

    let code: String
    let theme: String
    let errorMessage: String
    let textColor: PlatformColor
    let background: PlatformColor
    @Binding var height: CGFloat
    @Binding var isReady: Bool

    func makeCoordinator() -> MermaidCoordinator {
        MermaidCoordinator(
            code: code, theme: theme, errorMessage: errorMessage,
            textColor: textColor, background: background,
            height: $height, isReady: $isReady
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let view = MermaidCoordinator.makeWebView(delegate: context.coordinator)
        context.coordinator.load(into: view)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif

// MARK: - 描く手順

/// 器を読み込んで図を描く、という手順そのもの。
///
/// **拡大窓（`MermaidZoomWindow`）が継いで、描き方だけを差し替える。**
/// 器の置き場所と、外へ出さないための遷移の禁止は、ここ1か所に置く。
@MainActor
class MermaidCoordinator: NSObject, WKNavigationDelegate {

    let code: String
    let theme: String
    private let errorMessage: String
    private let textColor: PlatformColor
    private let background: PlatformColor
    @Binding private var height: CGFloat
    @Binding private var isReady: Bool

    init(
        code: String, theme: String, errorMessage: String,
        textColor: PlatformColor, background: PlatformColor,
        height: Binding<CGFloat>, isReady: Binding<Bool>
    ) {
        self.code = code
        self.theme = theme
        self.errorMessage = errorMessage
        self.textColor = textColor
        self.background = background
        self._height = height
        self._isReady = isReady
    }

    /// 器の置き場所。`host.html` は同じ folder の `mermaid.min.js` を相対で読む。
    static var hostURL: URL? {
        Bundle.module.url(forResource: "Mermaid/host", withExtension: "html")
    }

    /// - Parameter passesScrollThrough: ホイールを外へ素通しするか。
    ///   プレビューに埋めるときは `true`。拡大窓は自分でスクロールするので `false`。
    static func makeWebView(
        delegate: MermaidCoordinator, passesScrollThrough: Bool = false
    ) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // 図の中から新しい窓を開かせない。
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let frame = CGRect(x: 0, y: 0, width: 400, height: 24)
        #if canImport(AppKit)
        let view: WKWebView = passesScrollThrough
            ? ScrollThroughWebView(frame: frame, configuration: configuration)
            : WKWebView(frame: frame, configuration: configuration)
        #else
        // UIKit では、下で `scrollView.isScrollEnabled = false` にすれば
        // そのまま外のスクロールへ流れる。差し替えは要らない。
        let view = WKWebView(frame: frame, configuration: configuration)
        #endif
        view.navigationDelegate = delegate
        #if canImport(AppKit)
        // プレビューの地の色を透かす。WebView が自前の白を敷くと、
        // ダークのときに図のまわりだけ白い板が出る。
        view.setValue(false, forKey: "drawsBackground")
        #else
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.isScrollEnabled = false
        #endif
        return view
    }

    func load(into webView: WKWebView) {
        guard let host = Self.hostURL else {
            // 束に器が入っていない。作りの誤りなので、黙って消さずに知らせる。
            Trace.log("Mermaid: host.html が Bundle.module に無い")
            showError(in: webView)
            return
        }
        webView.loadFileURL(host, allowingReadAccessTo: host.deletingLastPathComponent())
    }

    // MARK: WKNavigationDelegate

    /// **器の読み込み以外は通さない。** 本文は他所から来た文書のことがある。
    /// 図の記述から外部へ出ていく経路を、頁の CSP と二重に塞ぐ。
    ///
    /// **署名を崩さないこと。** `nonisolated` にしたり、`decisionHandler` から
    /// `@MainActor` を落とすと省略可能な要件と「ほぼ一致」になり、
    /// **WebKit から呼ばれないまま素通しになる**（コンパイラは警告を出すが、
    /// エラーにはならない）。`MermaidNavigationTests` で見張っている。
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(allows(navigationAction.request.url) ? .allow : .cancel)
    }

    /// 通してよい遷移か。器そのもの（同梱したファイル）だけを通す。
    nonisolated static func allows(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.isFileURL
    }

    nonisolated func allows(_ url: URL?) -> Bool { Self.allows(url) }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { draw(in: webView) }
    }

    nonisolated func webView(
        _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
    ) {
        MainActor.assumeIsolated {
            Trace.log("Mermaid: 器を読み込めない \(error)")
            showError(in: webView)
        }
    }

    /// 器が読めたあとにすること。**継いだ側が差し替える。**
    func draw(in webView: WKWebView) {
        webView.callAsyncJavaScript(
            "return await renderDiagram(code, theme);",
            arguments: ["code": code, "theme": theme],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(value):
                guard let dictionary = value as? [String: Any],
                      dictionary["ok"] as? Bool == true,
                      let drawn = dictionary["height"] as? Double, drawn > 0
                else {
                    // mermaid が記述を読めなかった。**書きかけの最中はここを通る。**
                    let reason = (value as? [String: Any])?["reason"] as? String ?? "?"
    Trace.log("Mermaid: 描けない \(reason)")
                    self.showError(in: webView)
                    return
                }
                // **少しだけ余裕を持たせる。** 枠と中身がぴったりだと、
                // 丸めの差で中身がはみ出し、WebKit がホイールを飲むことがある。
                self.height = CGFloat(drawn) + 2
                self.isReady = true
                Trace.log("Mermaid: 高さ確定 \(Int(drawn)) pt")

            case let .failure(error):
                Trace.log("Mermaid: 描画を呼べない \(error)")
                self.showError(in: webView)
            }
        }
    }


    /// 描けなかったことを、図のあった場所に出す。**黙って消さない。**
    /// 何も出ないと、書いた本人には「プレビューが壊れた」としか見えない。
    func showError(in webView: WKWebView) {
        let message = errorMessage
        webView.callAsyncJavaScript(
            "return showError(message, textColor, background);",
            arguments: [
                "message": message,
                "textColor": textColor.cssColor,
                "background": background.cssColor,
            ],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self else { return }
            if case let .success(value) = result, let drawn = value as? Double, drawn > 0 {
                self.height = CGFloat(drawn)
            }
            // 器ごと読めていないときは高さが取れない。既定のままでも、
            // 何かが出ていることは分かる。
            self.isReady = true
        }
    }
}

// MARK: - 色の受け渡し

extension PlatformColor {
    /// 頁へ渡すための色。**外観を解いてから渡す。**
    /// 動的な色をそのまま数値にすると、いま画面に出ている側とは限らない。
    @MainActor var cssColor: String {
        #if canImport(AppKit)
        let resolved = usingColorSpace(.sRGB) ?? .textColor
        let red = Int((resolved.redComponent * 255).rounded())
        let green = Int((resolved.greenComponent * 255).rounded())
        let blue = Int((resolved.blueComponent * 255).rounded())
        let alpha = resolved.alphaComponent
        #else
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        let red = Int((r * 255).rounded())
        let green = Int((g * 255).rounded())
        let blue = Int((b * 255).rounded())
        let alpha = a
        #endif
        return "rgba(\(red), \(green), \(blue), \(String(format: "%.3f", alpha)))"
    }
}
