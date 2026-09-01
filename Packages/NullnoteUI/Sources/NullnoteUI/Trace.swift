import Foundation

/// 開発用の足あと。**`NULLNOTE_TRACE=1` を渡したときだけ**標準エラーに出す。
///
/// この環境では画面収録とアクセシビリティの権限が無く、UI を自動で動かせない。
/// 外の変更を取り込む経路のように「起きたかどうか」が画面にしか出ない仕組みは、
/// アプリに喋らせないと確かめられない。
///
/// ```sh
/// open -a /Applications/Nullnote.app --env NULLNOTE_TRACE=1 --stderr /tmp/log.txt file.md
/// ```
///
/// 既定では文字列の組み立てすら走らない（`@autoclosure`）ので、
/// 切ってあるあいだの費用はほぼゼロ。
public enum Trace {

    public static let isEnabled = ProcessInfo.processInfo.environment["NULLNOTE_TRACE"] == "1"

    public static func log(_ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        FileHandle.standardError.write(Data("[nullnote] \(message())\n".utf8))
    }
    /// プロセスが始まってからの経過（ミリ秒）。**起動の速さを測るときの基準。**
    public static var sinceLaunch: Double {
        -launchedAt.timeIntervalSinceNow * 1000
    }
    private static let launchedAt = Date()

    /// 中の処理にかかった時間を足あとに出す。
    ///
    /// **`NULLNOTE_TRACE=1` のときだけ測る。** 普段は `body` をそのまま呼ぶ。
    @discardableResult
    public static func time<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        guard isEnabled else { return try body() }
        let started = Date()
        let result = try body()
        let elapsed = -started.timeIntervalSinceNow * 1000
        log(String(format: "⏱ %@ %.1fms（起動から %.0fms）", label, elapsed, sinceLaunch))
        return result
    }

    /// その瞬間の時刻だけを出す。区間ではなく「いつ起きたか」を見るとき。
    public static func mark(_ label: String) {
        guard isEnabled else { return }
        log(String(format: "⏱ %@（起動から %.0fms）", label, sinceLaunch))
    }

}
