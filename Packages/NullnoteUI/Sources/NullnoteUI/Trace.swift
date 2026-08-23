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
}
