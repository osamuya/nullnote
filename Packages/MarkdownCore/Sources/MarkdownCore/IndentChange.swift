import Foundation

/// リストの行の深さを1段変える。
///
/// **副作用を持たない。** 行頭のインデントをどう書き換えるかだけを決める。
/// 実際に本文を触るのは呼ぶ側（`FocusReportingTextView.insertTab` / `insertBacktab`）。
///
/// ## 深くするとき
///
/// 設定で選んだ単位（スペース4 / スペース2 / タブ）を、**行頭に足す**。
///
/// ## 浅くするとき
///
/// **書かれているものを見て、1段ぶんを外す。** 設定は見ない。
/// スペースで書かれた文書をタブ設定で開いても、意図どおりに戻せるようにするため。
///
/// | 行頭 | 外すもの |
/// |---|---|
/// | タブで始まる | タブ1つ |
/// | スペースで始まる | **4桁のタブストップまで戻るぶん**（1〜4個） |
///
/// 4桁を基準にするのは、パーサがタブを4桁として数えているのに揃えるため
/// （`BlockScanner.indentWidth`）。`  - ` のような2つ刻みの文書でも、
/// 2つしか無ければ2つだけ外れるので、深さが飛ぶことはない。
public enum IndentChange {

    /// 深くする。`unit` は設定で選んだ1段ぶん。
    ///
    /// - Returns: 行頭に差し込む文字列。リストの行でなければ `nil`。
    public static func deepen(line: String, unit: String) -> String? {
        guard isListItem(line) else { return nil }
        return unit
    }

    /// 浅くする。
    ///
    /// - Returns: 行頭から外す文字数（UTF-16）。外すものが無ければ `nil`。
    public static func shallow(line: String) -> Int? {
        guard isListItem(line) else { return nil }

        var removed = 0
        var index = line.startIndex
        guard index < line.endIndex else { return nil }

        if line[index] == "\t" { return 1 }

        // スペースは、4桁の区切りまで戻るぶんだけ外す。
        var width = 0
        while index < line.endIndex, line[index] == " ", width < 4 {
            index = line.index(after: index)
            width += 1
            removed += 1
        }
        return removed > 0 ? removed : nil
    }

    /// インデントを別にすれば、リストの印で始まっている行か。
    ///
    /// **引用は数えない。** `>` の深さは意味が違い、インデントで表すものではない。
    private static func isListItem(_ line: String) -> Bool {
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        return BlockScanner.listMarker(line, index..<line.endIndex) != nil
    }
}
