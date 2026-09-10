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

/// 1枚しか無い窓にも、タブバーを出し続ける。
///
/// **要は取っ手。** 出ていないと、掴んで動かすところが無く、窓を結合しようがない
/// （macOS の既定では、2枚目のタブができるまで出ない）。決めた仕様は D-49。
///
/// ## `WindowConfigurator` から呼ぶだけでは足りない
///
/// あの中身が走るのは、**SwiftUI がビューを更新したときだけ**。
/// タブを**ドラッグ**で分けたときは窓の大きさと位置が変わり、そのついでに更新が走るので
/// 出ていた。ところが**「タブを新しいウインドウに移動」で分けたときは何も変わらない**ので
/// 更新が届かず、タブバーの無い窓が残っていた（#026）。
///
/// そこで、窓の動きを AppKit 側から受けて確かめ直す。
///
/// **窓そのものは覚えない。** 通知の中身も窓も他所へ渡せない（Swift 6）ので、
/// 覚えるのは書類の窓が共有するタブの識別子（文字列）だけにして、
/// 確かめるときに `NSApp.windows` から数え直す。
@MainActor
enum TabBarKeeper {

    /// 書類の窓が使うタブの識別子。`DocumentGroup` の窓はこれを共有する。
    private static var documentTabbingIdentifier: NSWindow.TabbingIdentifier?
    private static var observing = false
    /// 次の周回の確かめを、もう頼んであるか。
    private static var scheduled = false

    /// 書類の窓から呼ぶ。この窓の仲間には、1枚でもタブバーを出す。
    static func keepTabBar(on window: NSWindow) {
        documentTabbingIdentifier = window.tabbingIdentifier
        showIfAlone(window)
        startObserving()
    }

    /// 窓の動きを受け取る。**一度だけ登録する。**
    private static func startObserving() {
        guard !observing else { return }
        observing = true
        for name: Notification.Name in [
            // 分かれた窓が前に出る。
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            // ドラッグで分けたときは、位置と大きさが変わる。
            NSWindow.didMoveNotification,
            NSWindow.didResizeNotification,
        ] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { checkSoon() }
            }
        }
    }

    /// **次の周回で確かめる。** 通知が届いた時点では、タブ群がまだ
    /// 組み替わっていないことがある（分けた直後も、元の群にいるように見える）。
    ///
    /// 窓をドラッグしているあいだ `didMove` は何度も飛ぶので、まとめて1回にする。
    private static func checkSoon() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                scheduled = false
                guard let identifier = documentTabbingIdentifier else { return }
                for window in NSApp?.windows ?? []
                where window.isVisible && window.tabbingIdentifier == identifier {
                    showIfAlone(window)
                }
            }
        }
    }

    /// 1枚しか無い窓に、タブバーを出す。
    ///
    /// **毎回確かめて出し直す。** 出しっぱなしにするのが仕様なので、
    /// タブを引き出して1枚に戻った窓でも、また出す。
    /// そのぶんウインドウメニューの「タブバーを非表示」は効かなくなる。
    private static func showIfAlone(_ window: NSWindow) {
        guard let group = window.tabGroup,
              group.windows.count == 1,
              !group.isTabBarVisible
        else { return }
        window.toggleTabBar(nil)
    }
}

/// 書類の窓をタブとして扱う。
///
/// 決めた仕様はこの3つ（利用者と詰めた。D-49）。
///
/// | 操作 | どうなるか |
/// |---|---|
/// | 既存の md を開く | **新しい窓**。1枚でもタブバーを出し、タブが1つ付いた状態にする |
/// | ⌘N（新規書類） | **前面の窓の、新しいタブ** |
/// | タブをドラッグ | 窓同士を結合できる（AppKit の標準の動き） |
///
/// **1枚でもタブバーを出す**のが要。出ていないと、掴んで動かす取っ手が無く、
/// 窓を結合しようがない（macOS の既定では、2枚目のタブができるまで出ない）。
/// `isTabBarVisible` は読むだけなので、`toggleTabBar` で出す。
///
/// **開いた md を自動でタブへ入れない。** 入れると仕様1に反する。
/// `tabbingMode` は既定の `.automatic` のままにし、OS の
/// 「書類を開くときはタブで開く」に従わせる（既定は「フルスクリーンのときのみ」なので別窓になる）。
private struct TabbedWindows: ViewModifier {

    /// この窓が新規書類か。ファイルを持たずに現れた窓は ⌘N で作られたもの。
    let isNewDocument: Bool

    /// この窓で、もうまとめを試したか。窓ごとに1つ持つ。
    @State private var merge = MergeOnce()

    func body(content: Content) -> some View {
        content.background(
            WindowConfigurator { window in
                TabBarKeeper.keepTabBar(on: window)

                // ⌘N だけを前面の窓へ入れる。開いた md は別窓のままにする。
                guard isNewDocument, !merge.tried else { return }
                merge.tried = true

                // **`tabGroup` は nil にならない。** 単独の窓も1枚だけのタブ群を持つ（実測）。
                // 2枚以上なら、もうどこかのタブになっている。
                guard (window.tabGroup?.windows.count ?? 1) <= 1 else { return }
                // **`orderedWindows` を使う。** `NSApp.windows` は前後の順を保証しない
                // （実測: 手前が `tab_b` のときに `tab_a` を拾った）。
                // 新しい窓はすでに手前なので、自分を除いた先頭が ⌘N を押した窓。
                guard let host = NSApp.orderedWindows.first(where: {
                    $0 !== window
                        && $0.isVisible
                        && $0.tabbingIdentifier == window.tabbingIdentifier
                }) else { return }

                host.addTabbedWindow(window, ordered: .above)
                window.makeKeyAndOrderFront(nil)
            }
            .frame(width: 0, height: 0)
        )
    }

    /// 一度きりの合図を持つ入れ物。`@State` に置いて、窓が生きているあいだ残す。
    private final class MergeOnce {
        var tried = false
    }
}

extension View {

    /// 書類の窓をタブとして扱う。新規書類（`isNewDocument`）は前面の窓のタブにする。
    func tabbedWindows(isNewDocument: Bool) -> some View {
        modifier(TabbedWindows(isNewDocument: isNewDocument))
    }
}
