import Foundation

/// 合流のときに、空白の違いをどう扱うか。
///
/// **本文は書き換えない。比べ方だけを変える。**
/// どちらを採るかが決まったあとは、元の文字がそのまま出る。
public enum WhitespacePolicy: String, CaseIterable, Sendable {

    /// 1文字でも違えば違う行。
    case strict

    /// **行の途中の空白の量だけ無視する。** 行頭のインデントと行末は、そのまま比べる。
    ///
    /// | | |
    /// |---|---|
    /// | `# here` と `#  here` | 同じ |
    /// | `- a \| b` と `- a  \|  b` | 同じ |
    /// | `  - item` と `    - item` | **違う**（入れ子の深さ） |
    /// | `foo  ` と `foo` | **違う**（行末2つは改行） |
    ///
    /// `git diff -b` は行頭・行末も含めて量を無視するが、**Markdown ではその2つが意味を持つ**。
    /// 入れ子の深さと、行末2つの空白による改行。だからそこは触らない。判断の記録は D-47。
    case ignoreInnerRuns

    /// 2つの行を、この方針で同じとみなすか。
    public func equal(_ a: String, _ b: String) -> Bool {
        switch self {
        case .strict: a == b
        case .ignoreInnerRuns: key(a) == key(b)
        }
    }

    /// 比較に使う形。**同じ行なら同じ文字列になる。**
    ///
    /// 行頭の空白と行末の空白はそのまま残し、あいだの連続する空白だけを1つに詰める。
    public func key(_ line: String) -> String {
        guard self == .ignoreInnerRuns else { return line }

        // 行頭。書かれたとおりに残す（タブと空白も区別する）。
        var index = line.startIndex
        while index < line.endIndex, line[index] == " " || line[index] == "\t" {
            index = line.index(after: index)
        }
        let leading = line[line.startIndex..<index]

        // 行末。同じく残す。
        var end = line.endIndex
        while end > index {
            let previous = line.index(before: end)
            guard line[previous] == " " || line[previous] == "\t" else { break }
            end = previous
        }
        let trailing = line[end..<line.endIndex]

        // 中身。連続する空白を1つに詰める。
        var middle = ""
        var inRun = false
        for character in line[index..<end] {
            if character == " " || character == "\t" {
                if !inRun { middle.append(" ") ; inRun = true }
            } else {
                middle.append(character)
                inRun = false
            }
        }
        return leading + middle + trailing
    }
}
