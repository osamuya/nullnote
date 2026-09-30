import AppKit
import NullnoteUI

/// ⌘N で窓がもう一方の画面へ移る件（#033）を見るための足あと。**原因が決まったら外す。**
///
/// 見立ては2つ（どちらも実機では確かめていない）。
///
/// - 新しい窓は、直前に置いた窓からずらして出る。それがサブの画面だと、そこに出る。
/// - 前面の窓へまとめる処理（`TabbedWindows`）は `WindowConfigurator` 頼みで、
///   窓に載る前に呼ばれると何もせずに終わる。まとめられなければ、窓はサブの画面に残る。
///
/// どちらが起きているかを、窓の位置と画面の番号で喋らせる。
/// `NULLNOTE_TRACE=1` のときだけ動く。切ってあるあいだは何も登録しない。
@MainActor
enum WindowPlacementTrace {

    private static var started = false

    /// 見張りを始める。起動時に一度だけ呼ぶ。
    static func start() {
        guard Trace.isEnabled, !started else { return }
        started = true

        Trace.log("配置 画面 " + NSScreen.screens.enumerated().map { index, screen in
            "#\(index)=\(rect(screen.frame))"
        }.joined(separator: " "))

        // **`note.object` は使わない。** 通知の中身は他所へ渡せない（Swift 6）ので、
        // 合図として受け、窓は自分で数え直す。
        NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { snapshot("★窓の画面が変わった") }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { snapshot("手前の窓が変わった") }
        }
    }

    /// 1行だけ出す。
    static func log(_ message: @autoclosure () -> String) {
        guard Trace.isEnabled else { return }
        Trace.log("配置 \(message())")
    }

    /// 見えている窓を、手前から並べて出す。
    static func snapshot(_ label: String) {
        guard Trace.isEnabled else { return }
        let lines = (NSApp?.orderedWindows ?? []).filter(\.isVisible).map {
            "    \(describe($0))"
        }
        Trace.log("配置 【\(label)】\n" + lines.joined(separator: "\n"))
    }

    /// 窓の名前・画面の番号・位置・タブの枚数。
    static func describe(_ window: NSWindow) -> String {
        let title = window.title.isEmpty ? "無題" : window.title
        let screen = window.screen.flatMap { current in
            NSScreen.screens.firstIndex(of: current)
        }.map { "#\($0)" } ?? "なし"
        let tabs = window.tabGroup?.windows.count ?? 0
        let flags = [window.isKeyWindow ? "key" : nil, window.isVisible ? nil : "非表示"]
            .compactMap { $0 }.joined(separator: ",")
        // 本文がタイトルバーの下へ潜る指定。`straightHeader` が外すもの。
        let under = window.styleMask.contains(.fullSizeContentView) ? "あり" : "なし"
        return "「\(title)」 画面\(screen) \(rect(window.frame)) タブ=\(tabs) 潜り=\(under)"
            + (flags.isEmpty ? "" : " [\(flags)]")
    }

    private static func rect(_ rect: NSRect) -> String {
        String(format: "(%.0f,%.0f %.0fx%.0f)", rect.minX, rect.minY, rect.width, rect.height)
    }
}
