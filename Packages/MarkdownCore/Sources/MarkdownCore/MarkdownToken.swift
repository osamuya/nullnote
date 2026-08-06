import Foundation

/// ソース上の範囲と、そこに与えるべき意味づけの組。
///
/// ネストしたドキュメント木は持たない。エディタのシンタックスハイライト
/// （`NSTextStorage` / `NSAttributedString` への属性適用）に必要な最小限の情報だけを運ぶ。
///
/// ## 範囲の重なりについて
/// トークンは重なることがある。`# **見出し**` は見出しトークンと強調トークンの両方を生む。
/// 配列は **外側のトークンが内側より先** に並ぶため、配列順どおりに属性を適用すれば
/// 内側の指定が外側を上書きして正しく重なる。
public struct MarkdownToken: Hashable, Sendable {

    /// 記法そのものを表す文字（本文ではない部分）。エディタでは薄く表示することが多い。
    public enum Marker: Hashable, Sendable {
        /// 見出しの `#` 列。
        case heading
        /// リストの `-` `*` `+` `1.` `1)`。
        case list
        /// 引用の `>`。
        case blockQuote
        /// 水平線 `---` `***` `___` の行全体。
        case thematicBreak
        /// コードフェンス ` ``` ` `~~~`。
        case codeFence
        /// 強調の `*` `_`。
        case emphasis
        /// 強い強調の `**` `__`（`***` も含む）。
        case strong
        /// 取り消し線の `~` `~~`。
        case strikethrough
        /// インラインコードのバッククォート。
        case inlineCode
        /// 表の区切り `|`。
        case tablePipe
        /// リンク・画像の `[` `]` `![`。
        case linkBracket
        /// リンク先を囲む `(` `)`。
        case linkParen
        /// オートリンクを囲む `<` `>`。
        case autolinkAngle
        /// バックスラッシュエスケープの `\`。
        case escape
    }

    public enum Kind: Hashable, Sendable {
        /// 記法文字そのもの。
        case marker(Marker)
        /// 見出しの本文。`level` は 1...6。
        case heading(level: Int)
        /// 引用の本文。
        case blockQuote
        /// フェンス付き／インデントされたコードブロックの中身。
        case codeBlock
        /// フェンス直後の情報文字列（` ```swift ` の `swift`）。
        case codeLanguage
        /// 強調の本文。
        case emphasis
        /// 強い強調の本文。
        case strong
        /// 取り消し線の本文。
        case strikethrough
        /// インラインコードの中身。
        case inlineCode
        /// タスクリストのチェックボックス `[ ]` `[x]` 全体。
        case taskMarker(isChecked: Bool)
        /// 表のヘッダ行のセル。
        case tableHeaderCell
        /// 表の区切り行のセル（`---` `:-:`）。
        case tableDelimiterCell
        /// 表の本体行のセル。
        case tableCell
        /// `[表示テキスト]` の中身。
        case linkText
        /// `(リンク先)` の中身。
        case linkURL
        /// リンクとして解釈される URL・メールアドレス。
        /// `<https://example.com>` の中身と、山括弧の無い裸の URL の両方で使う。
        case autolink
        /// バックスラッシュでエスケープされた1文字。
        case escapedCharacter
    }

    public let kind: Kind
    public let range: Range<String.Index>

    public init(kind: Kind, range: Range<String.Index>) {
        self.kind = kind
        self.range = range
    }
}

extension MarkdownToken {
    /// `NSTextStorage` などの UTF-16 ベース API へ渡すための範囲。
    ///
    /// - Important: トークンを取り出したときと同じ文字列を渡すこと。
    ///   変換は文字列先頭からの距離に比例するため、行ごとにまとめて変換すると効率が良い。
    public func nsRange(in text: String) -> NSRange {
        NSRange(range, in: text)
    }
}
