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

/// ビューが窓に載った瞬間に一度だけ呼ぶ。
///
/// `WindowConfigurator` は1周待ってから走るので、そのときには窓がもう画面に出ている。
/// こちらは `viewDidMoveToWindow` でその場で呼ぶので、**窓が画面に出る前**に手を入れられる（#M0040）。
struct WindowAttachHook: NSViewRepresentable {

    let attached: (NSWindow) -> Void

    func makeNSView(context: Context) -> HookView {
        let view = HookView()
        view.attached = attached
        return view
    }

    func updateNSView(_ view: HookView, context: Context) {
        view.attached = attached
    }

    final class HookView: NSView {
        var attached: ((NSWindow) -> Void)?
        private var done = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // 外されたとき（`window == nil`）と、二度目以降は何もしない。
            guard !done, let window else { return }
            done = true
            attached?(window)
        }
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
                WindowHeader.straighten(window)
            }
            .frame(width: 0, height: 0)
        )
    }
}

/// ヘッダを帯として見せるための、窓の設定。`straightHeader` の中身。
///
/// ⌘N の窓では、画面に出る前（`WindowAttachHook`）にも呼ぶ（#M0040）。
@MainActor
enum WindowHeader {

    static func straighten(_ window: NSWindow) {
        // 本文をタイトルバーの下へ潜らせない。
        // 潜らせたままだと、列ごとに下地が違うのでヘッダの帯が途切れて見える。
        //
        // **外したら窓の大きさを戻す。** AppKit は中身の大きさを保ったまま、
        // タイトルバーの分だけ窓を**上へ**伸ばす（実測: 400 → 466、下の辺は動かない）。
        // ⌘N のタブでは、ここを通るのがタブへまとめた後になることがあり、
        // まとめ先の大きさから伸びる。戻さないと押すたびに 88pt ずつ積み上がり、
        // 真上にあるサブの画面へはみ出して、窓ごと移ったように見えていた（#M0039・D-66）。
        if window.styleMask.contains(.fullSizeContentView) {
            let frame = window.frame
            window.styleMask.remove(.fullSizeContentView)
            if window.frame != frame {
                window.setFrame(frame, display: true)
            }
        }
        if window.titlebarSeparatorStyle != .line {
            window.titlebarSeparatorStyle = .line
        }
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
/// 更新が届かず、タブバーの無い窓が残っていた（#M0029）。
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
        content
            // **窓が画面に出る前に**まとめる（#M0040）。ビューが窓に載った瞬間は、
            // まだ画面に出ていない（実測: `isVisible == false`）。ここでタブへ入れれば、
            // 単独の窓として右下にずれて一瞬出る姿を見せずに済む。
            .background(
                WindowAttachHook { window in
                    guard isNewDocument, !window.isVisible else { return }
                    // タイトルバーの指定も、出る前に外しておく。まとめた後で外すと、
                    // 並んだタブの上で中身がずれて描き直される。
                    WindowHeader.straighten(window)
                    joinFrontWindow(window)
                }
                .frame(width: 0, height: 0)
            )
            .background(
                WindowConfigurator { window in
                    TabBarKeeper.keepTabBar(on: window)
                    // 出る前にまとめられなかったときの受け皿。出てからまとめる。
                    guard isNewDocument, joinFrontWindow(window) else { return }
                    window.makeKeyAndOrderFront(nil)
                }
                .frame(width: 0, height: 0)
            )
    }

    /// ⌘N の窓を、前面の書類の窓のタブへ入れる。**窓につき一度だけ試す。**
    ///
    /// 開いた md は別窓のままにする（呼ぶ側が `isNewDocument` で絞る）。
    /// - Returns: まとめたか。
    @discardableResult
    private func joinFrontWindow(_ window: NSWindow) -> Bool {
        guard !merge.tried else { return false }
        merge.tried = true

        // **`tabGroup` は nil にならない。** 単独の窓も1枚だけのタブ群を持つ（実測）。
        // 2枚以上なら、もうどこかのタブになっている。
        guard (window.tabGroup?.windows.count ?? 1) <= 1 else { return false }
        // **`orderedWindows` を使う。** `NSApp.windows` は前後の順を保証しない
        // （実測: 手前が `tab_b` のときに `tab_a` を拾った）。
        // 自分を除いた、見えている先頭が ⌘N を押した窓。
        guard let host = NSApp.orderedWindows.first(where: {
            $0 !== window
                && $0.isVisible
                && $0.tabbingIdentifier == window.tabbingIdentifier
        }) else { return false }

        // 画面に出ていない窓でもタブへ入る。出るのは、入ったあと（実測）。
        host.addTabbedWindow(window, ordered: .above)
        // **大きさをまとめ先にそろえる。** 出る前の窓にはまだタブバーが無く、
        // AppKit は群のタブバーの分だけ窓を下へ伸ばす（実測: 450 → 486）。
        if window.frame != host.frame {
            window.setFrame(host.frame, display: false)
        }
        return true
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
