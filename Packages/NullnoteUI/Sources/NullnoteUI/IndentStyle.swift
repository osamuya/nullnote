import Foundation

/// リストの深さを1段変えるときに、何を入れるか。
///
/// **既にある行のインデントは触らない。** 継ぎ足し（`LineContinuationRule`）は
/// 書かれた文字をそのまま複写するので、この設定に関係なく元の形が保たれる。
/// ここが効くのは、**新しく深くするとき**だけ。
///
/// ## なぜ選べるようにしたか
///
/// Markdown のファイルとしてはスペースが多数派で、`markdownlint` の `MD010` は
/// 既定でタブを咎める。一方、書いたものが自分の中で完結するならタブでよく、
/// メモアプリにはタブを既定にしているものもある。**正誤ではなく好みの側の話**なので、
/// 決め打ちにしない。判断の記録は `docs/02-decision-log.md` の D-39。
///
/// 自前のパーサはタブを4桁のタブストップとして数えているので
/// （`BlockScanner.indentWidth`）、どれを選んでも解釈は CommonMark と揃う。
public enum IndentStyle: String, CaseIterable, Identifiable, Sendable {
    case fourSpaces
    case twoSpaces
    case tab

    public var id: String { rawValue }

    /// 1段ぶんの文字列。
    public var unit: String {
        switch self {
        case .fourSpaces: "    "
        case .twoSpaces: "  "
        case .tab: "\t"
        }
    }

    public var label: String {
        switch self {
        case .fourSpaces: "スペース4"
        case .twoSpaces: "スペース2"
        case .tab: "タブ"
        }
    }
}
