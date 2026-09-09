import AppKit
import NullnoteUI

/// ウインドウに掛けた外観の指定が、**いつ外れるか**を見るための足あと（#023）。
///
/// フォルダの許可を出すと、テーマがライトのままなのに画面がダークに落ちる。
/// 保存されている設定は `light` のままなので、書き換わったのではなく
/// **ウインドウの `appearance` が外れてシステムの値に落ちている**という見立て。
/// 見立てのままでは直せないので、外れた瞬間を喋らせる。
///
/// `NULLNOTE_TRACE=1` のときだけ動く。切ってあるあいだは何も登録しない。
@MainActor
enum AppearanceTrace {

    /// 見張っている窓。窓ごとに1つ。
    private static var watchers: [ObjectIdentifier: NSKeyValueObservation] = [:]
    /// 直前に見た指定。KVO の `change` は他所へ渡せない（Swift 6）ので自分で覚える。
    private static var previous: [ObjectIdentifier: String] = [:]
    private static var appWatcher: NSKeyValueObservation?
    private static var started = false

    /// 見張りを始める。起動時に一度だけ呼ぶ。
    static func start() {
        guard Trace.isEnabled, !started else { return }
        started = true

        appWatcher = NSApp?.observe(\.effectiveAppearance) { app, _ in
            MainActor.assumeIsolated {
                Trace.log("外観 NSApp の実効が変わった → \(app.effectiveAppearance.name.rawValue)")
            }
        }

        // 窓は後からできる。何か動きがあるたびに、まだ見ていない窓を拾う。
        // **`note.object` は使わない。** 通知の中身は他所へ渡せない（Swift 6）ので、
        // 合図として受け、窓は自分で数え直す。
        for name: Notification.Name in [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didUpdateNotification,
        ] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { watchAll() }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { snapshot("アプリが手前に戻った") }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { snapshot("アプリが後ろへ回った") }
        }
    }

    /// まだ見ていない窓を見張りに加える。
    private static func watchAll() {
        for window in NSApp?.windows ?? [] {
            let key = ObjectIdentifier(window)
            guard watchers[key] == nil else { continue }
            previous[key] = specified(window)
            Trace.log(
                "外観 見張り開始 \(label(window)) 指定=\(specified(window))"
                    + " 実効=\(window.effectiveAppearance.name.rawValue)"
            )
            // **`change` を受け取らない。** 中身を `MainActor` へ渡せないため、
            // 前の値は `previous` に自分で控える。
            watchers[key] = window.observe(\.appearance) { window, _ in
                MainActor.assumeIsolated {
                    let key = ObjectIdentifier(window)
                    let before = previous[key] ?? "?"
                    let after = specified(window)
                    previous[key] = after
                    guard before != after else { return }
                    Trace.log(
                        "外観 ★指定が変わった \(label(window)) \(before) → \(after)"
                            + " 実効=\(window.effectiveAppearance.name.rawValue)"
                    )
                }
            }
        }
    }

    /// 直前に見た設定の値。
    private static var lastValue: MarkdownAppearance?

    /// 画面が使っている**設定の値**を見る。窓の外観とは別の経路。
    ///
    /// 疑っているのはこちら。フォルダのパネルは別プロセスで動いていて、
    /// **閉じるときにアプリの設定ドメインへ書き込む**（`AppSettings` の B-16）。
    /// その書き込みで `@AppStorage` が読み直したときに `editorAppearance` を
    /// 拾い損ねると、既定の `.system` に落ちる。ディスクの値は `light` のまま
    /// なので、`defaults read` では何も起きていないように見える。
    static func note(_ appearance: MarkdownAppearance) {
        guard Trace.isEnabled, lastValue != appearance else { return }
        let onDisk = UserDefaults.standard.string(forKey: AppSettings.appearanceKey) ?? "なし"
        Trace.log(
            "外観 ◆設定の値が変わった \(lastValue?.rawValue ?? "初回") → \(appearance.rawValue)"
                + " ディスク=\(onDisk)"
        )
        lastValue = appearance
    }

    /// いまの状態をまとめて出す。区切りの場面で呼ぶ。
    static func snapshot(_ label: String) {
        guard Trace.isEnabled else { return }
        let lines = (NSApp?.windows ?? []).filter(\.isVisible).map {
            "    \(self.label($0)) 指定=\(specified($0)) 実効=\($0.effectiveAppearance.name.rawValue)"
        }
        Trace.log(
            "外観 【\(label)】 NSApp指定=\(NSApp?.appearance?.name.rawValue ?? "なし")"
                + " NSApp実効=\(NSApp?.effectiveAppearance.name.rawValue ?? "?")\n"
                + lines.joined(separator: "\n")
        )
    }

    private static func specified(_ window: NSWindow) -> String {
        window.appearance?.name.rawValue ?? "なし（親から継承）"
    }

    private static func label(_ window: NSWindow) -> String {
        let kind = String(describing: type(of: window))
        let title = window.title.isEmpty ? "無題" : window.title
        return "\(kind)「\(title)」"
    }
}
