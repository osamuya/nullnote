import Foundation
import MarkdownCore

/// トークンの種類と、それが指すソース文字列の組。テストの期待値を読みやすくするための補助型。
struct TokenSnapshot: Equatable, CustomStringConvertible {
    let kind: MarkdownToken.Kind
    let text: String

    init(_ kind: MarkdownToken.Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    var description: String { "\(kind) → \"\(text)\"" }
}

extension MarkdownTokenizer {
    /// 文書全体をトークン化し、比較しやすい形に落とす。
    static func snapshot(_ source: String) -> [TokenSnapshot] {
        MarkdownTokenizer().tokenize(source).map {
            TokenSnapshot($0.kind, String(source[$0.range]))
        }
    }

    /// 行ごとに分けたスナップショット。
    static func lineSnapshots(_ source: String) -> [[TokenSnapshot]] {
        MarkdownTokenizer().tokenizeLines(source).map { line in
            line.tokens.map { TokenSnapshot($0.kind, String(source[$0.range])) }
        }
    }
}
