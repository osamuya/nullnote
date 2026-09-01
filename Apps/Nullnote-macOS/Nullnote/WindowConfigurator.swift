import AppKit
import SwiftUI

/// 載っているウインドウに一度だけ手を入れる。
///
/// SwiftUI から届かない `NSWindow` の設定はここで行う。
/// 見えないビューを1枚挟むだけで、レイアウトには影響しない。
struct WindowConfigurator: NSViewRepresentable {

    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        // `makeNSView` の時点ではまだウインドウに載っていない。
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window else { return }
            configure(window)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let window = view.window else { return }
        configure(window)
    }
}

extension View {

    /// タイトルにプロキシアイコンを持たせる。
    ///
    /// `representedURL` を入れると、macOS が**タイトルの右クリック（⌘クリックでも）**に
    /// フォルダの階層メニューを出す。選んだ階層が Finder で開く。**標準の仕組み。**
    ///
    /// アイコンはタイトルに重ねて出るので、こちらで描くものは無い。
    /// ファイルが変わったら差し替える。新規書類（`fileURL` が nil）なら外す。
    func proxyIcon(for fileURL: URL?) -> some View {
        background(
            WindowConfigurator { window in
                guard window.representedURL != fileURL else { return }
                window.representedURL = fileURL
            }
            .frame(width: 0, height: 0)
            // 開いているファイルが変わったら、載せ直して設定を反映させる。
            .id(fileURL)
        )
    }

    /// ヘッダ（タイトルバー）を、窓の幅いっぱいの帯として見せる。
    ///
    /// SwiftUI の既定では、窓は `.fullSizeContentView` で開き、
    /// **`ScrollView` と `List` はタイトルバーの下まで伸びる**（本文が下を流れる作り）。
    /// 一方 `NSViewRepresentable` で載せたエディタは safe area を守って下から始まる。
    /// その結果、列ごとにタイトルバーの下地が変わり、帯が途切れて見えていた。
    ///
    /// 実測（目次・編集・プレビューを開いた状態、タイトルバー 52pt）:
    ///
    /// | 列 | スクロールビューの上端 |
    /// |---|---|
    /// | 目次（`List`） | 0 pt |
    /// | 編集（`NSScrollView`） | 52 pt |
    /// | プレビュー（`ScrollView`） | 0 pt |
    func straightHeader() -> some View {
        background(
            WindowConfigurator { window in
                // 本文をタイトルバーの下へ潜らせない。
                // 潜らせたままだと、列ごとに下地が違うのでヘッダの帯が途切れて見える。
                if window.styleMask.contains(.fullSizeContentView) {
                    window.styleMask.remove(.fullSizeContentView)
                }
                if window.titlebarSeparatorStyle != .line {
                    window.titlebarSeparatorStyle = .line
                }
            }
            .frame(width: 0, height: 0)
        )
    }
}
