import Foundation

/// 行の境界におけるブロック解析の状態。
///
/// 1行のトークン化は「直前の状態」だけで決まるように設計してある。
/// これにより、編集された行から再解析を始め、状態が元と一致した時点で打ち切る
/// 差分更新を、モデルを変えずに後から載せられる。
public enum MarkdownBlockState: Hashable, Sendable {

    public enum FenceMarker: Character, Hashable, Sendable {
        case backtick = "`"
        case tilde = "~"
    }

    /// 直前が空行、または文書の先頭。
    case blank
    /// 直前が段落・リスト項目など、テキストが続いている行。
    case paragraph
    /// インデント（4カラム以上）によるコードブロックの途中。
    case indentedCode
    /// フェンスが開いたまま。`length` 以上の同じ記号だけの行で閉じる。
    case fencedCode(marker: FenceMarker, length: Int)
    /// 直前が表のヘッダ行。次の行は区切り行でなければならない。
    case tableDelimiterExpected(columnCount: Int)
    /// 表の本体。空行か別のブロックの開始で終わる。
    case tableBody(columnCount: Int)
    /// 閉じていない HTML コメント（`<!--`）の中。
    ///
    /// `insideParagraph` は、コメントが**段落の途中から**始まったか。
    /// 行頭から始まったものは CommonMark の HTML ブロック（type 2）で、
    /// `-->` のある行が**まるごと**コメントになる。
    /// 段落の途中から始まったものはインラインの生 HTML で、
    /// `-->` の**あとは本文が続く**。閉じ方が違うので区別して持つ。
    ///
    /// どちらも**空行では終わらない**。終わるのは `-->` か文書の終わり。
    case htmlComment(insideParagraph: Bool)
}
