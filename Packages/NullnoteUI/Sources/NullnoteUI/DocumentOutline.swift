import Foundation
import MarkdownCore

/// 目次の1項目。見出しひとつに対応する。
public struct OutlineItem: Identifiable, Hashable, Sendable {

    public let id: Int
    /// 見出しの深さ。1 が `#`。
    public let level: Int
    /// 記法文字を除いた見出しの文字列。
    public let title: String
    /// 元の Markdown の何行目か。1 始まり。
    public let line: Int
    /// 下位の見出し。無い場合は `nil`。
    ///
    /// `List(children:)` は空配列でも開閉の三角を出してしまうので、
    /// 子が無いときは `nil` にする。
    public let children: [OutlineItem]?

    public init(id: Int, level: Int, title: String, line: Int, children: [OutlineItem]?) {
        self.id = id
        self.level = level
        self.title = title
        self.line = line
        self.children = children
    }
}

/// Markdown から見出しの階層を組み立てる。
///
/// `MarkdownCore` のトークンをそのまま使う。見出しの範囲と、その中の記法文字の
/// 範囲が分かるので、`**強調**` のような記法を取り除いた文字列を作れる。
public enum DocumentOutline {

    /// 見出しを階層構造にして返す。見出しが無ければ空。
    public static func build(from source: String) -> [OutlineItem] {
        var flat: [(level: Int, title: String, line: Int)] = []

        for (offset, line) in MarkdownTokenizer().tokenizeLines(source).enumerated() {
            guard let heading = headingToken(in: line) else { continue }
            let title = MarkdownPlainText.text(of: heading.range, in: source, tokens: line.tokens)
            guard !title.isEmpty else { continue }
            flat.append((level: heading.level, title: title, line: offset + 1))
        }

        var counter = 0
        return nest(flat[...], counter: &counter)
    }

    // MARK: - 走査

    private static func headingToken(in line: MarkdownLineTokens) -> (level: Int, range: Range<String.Index>)? {
        for token in line.tokens {
            if case .heading(let level) = token.kind {
                return (level, token.range)
            }
        }
        return nil
    }

    // MARK: - 階層化

    /// 平たい並びを、レベルの深さで入れ子にする。
    ///
    /// 先頭より浅い見出しが後から出てきた場合（`##` の次に `#`）は、
    /// そこで区切って同じ階層に並べる。文書の見出しレベルが飛んでいても壊れない。
    private static func nest(
        _ items: ArraySlice<(level: Int, title: String, line: Int)>,
        counter: inout Int
    ) -> [OutlineItem] {
        var result: [OutlineItem] = []
        var index = items.startIndex

        while index < items.endIndex {
            let current = items[index]
            // 自分より深い見出しが続く範囲が、この見出しの子。
            var childEnd = items.index(after: index)
            while childEnd < items.endIndex, items[childEnd].level > current.level {
                childEnd = items.index(after: childEnd)
            }

            counter += 1
            let id = counter
            let children = nest(items[items.index(after: index)..<childEnd], counter: &counter)

            result.append(OutlineItem(
                id: id,
                level: current.level,
                title: current.title,
                line: current.line,
                children: children.isEmpty ? nil : children
            ))
            index = childEnd
        }
        return result
    }
}

extension Array where Element == OutlineItem {
    /// 階層を平たくして数える。テストと「全部開く」の判定に使う。
    public var flattened: [OutlineItem] {
        flatMap { [$0] + ($0.children?.flattened ?? []) }
    }
}
