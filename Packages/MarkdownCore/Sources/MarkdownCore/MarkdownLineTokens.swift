import Foundation

/// 1行分のトークン化結果。
public struct MarkdownLineTokens: Hashable, Sendable {

    /// 改行文字を含まない行本体の範囲。
    public let range: Range<String.Index>
    /// この行に入る直前のブロック状態。
    public let stateBefore: MarkdownBlockState
    /// この行を処理し終えたあとのブロック状態。次の行の `stateBefore` になる。
    public let stateAfter: MarkdownBlockState
    /// 外側から内側の順に並んだトークン。
    public let tokens: [MarkdownToken]

    public init(
        range: Range<String.Index>,
        stateBefore: MarkdownBlockState,
        stateAfter: MarkdownBlockState,
        tokens: [MarkdownToken]
    ) {
        self.range = range
        self.stateBefore = stateBefore
        self.stateAfter = stateAfter
        self.tokens = tokens
    }
}
