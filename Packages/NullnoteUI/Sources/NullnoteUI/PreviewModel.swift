import Foundation
import Markdown
import SwiftUI

// プレビューの中間表現。
//
// swift-markdown の AST をそのまま SwiftUI に渡すと、ビューの組み立てと
// AST の歩き方が混ざって読めなくなる。ブロック構造だけをここで平たくし、
// インラインは `AttributedString` に畳んでおく。
//
// `Markdown.Text` と `SwiftUI.Text` がぶつかるので、このファイルでは
// swift-markdown の型を必ず `Markdown.` で修飾する。

/// プレビューが描くブロック要素。
struct PreviewBlock: Identifiable {
    let id: Int
    /// このブロックが元の Markdown の何行目から始まるか。1 始まり。
    /// エディタとのスクロール同期は、この行番号を手がかりにする。
    let sourceLine: Int
    let content: Content

    indirect enum Content {
        case heading(level: Int, text: AttributedString)
        case paragraph(AttributedString)
        case quote([PreviewBlock])
        case list(PreviewList)
        case codeBlock(code: String, language: String?)
        case table(PreviewTable)
        case thematicBreak
    }
}

struct PreviewList {
    let isOrdered: Bool
    let start: Int
    let items: [PreviewListItem]
}

struct PreviewListItem: Identifiable {
    let id: Int
    /// タスクリストの場合のみ。`nil` は通常の項目。
    let isChecked: Bool?
    let blocks: [PreviewBlock]
}

struct PreviewTable {
    let alignments: [PreviewColumnAlignment]
    let header: [AttributedString]
    let rows: [[AttributedString]]
}

enum PreviewColumnAlignment {
    case leading, center, trailing
}

extension Array where Element == PreviewBlock {
    /// その行を含むブロックの id。
    ///
    /// ブロックは `sourceLine` の昇順に並んでいる前提。
    /// 指定の行から始まるブロックが無ければ、その行より手前で最も近いものを返す
    /// （段落の途中を指されたときに、その段落の先頭へ合わせるため）。
    func blockID(containing line: Int) -> Int? {
        var match: Int?
        for block in self {
            guard block.sourceLine <= line else { break }
            match = block.id
        }
        return match ?? first?.id
    }
}

// MARK: - 構築

struct PreviewBuilder {

    private let theme: MarkdownTheme
    private var counter = 0
    /// 行番号を持たないノードに与える値。直前に分かっている行を引き継ぐ。
    private var lastKnownLine = 1

    static func build(_ source: String, theme: MarkdownTheme) -> [PreviewBlock] {
        var builder = PreviewBuilder(theme: theme)
        return builder.blocks(in: Document(parsing: source))
    }

    // MARK: ブロック

    private mutating func blocks(in markup: Markup) -> [PreviewBlock] {
        markup.children.compactMap { block(from: $0) }
    }

    private mutating func block(from markup: Markup) -> PreviewBlock? {
        // 子を辿ると lastKnownLine が進んでしまうので、先に自分の行を控える。
        let line = markup.range?.lowerBound.line ?? lastKnownLine
        lastKnownLine = line

        guard let content = content(from: markup) else { return nil }
        counter += 1
        return PreviewBlock(id: counter, sourceLine: line, content: content)
    }

    private mutating func content(from markup: Markup) -> PreviewBlock.Content? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, text: inlineText(heading))

        case let paragraph as Paragraph:
            return .paragraph(inlineText(paragraph))

        case let quote as BlockQuote:
            return .quote(blocks(in: quote))

        case let list as UnorderedList:
            return .list(PreviewList(isOrdered: false, start: 1, items: items(in: list)))

        case let list as OrderedList:
            return .list(
                PreviewList(isOrdered: true, start: Int(list.startIndex), items: items(in: list))
            )

        case let code as CodeBlock:
            // 末尾の改行は表示上ノイズになるので落とす。
            let body = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            return .codeBlock(code: body, language: code.language)

        case let table as Markdown.Table:
            return .table(previewTable(table))

        case is ThematicBreak:
            return .thematicBreak

        case let html as HTMLBlock:
            // HTML は解釈せず、そのまま見せる。
            return .codeBlock(code: html.rawHTML.trimmingCharacters(in: .newlines), language: "html")

        default:
            // 未知のブロックは中身だけ拾う。取りこぼすより落とさない方を選ぶ。
            let text = inlineText(markup)
            return text.characters.isEmpty ? nil : .paragraph(text)
        }
    }

    private mutating func items(in list: Markup) -> [PreviewListItem] {
        var result: [PreviewListItem] = []
        for child in list.children {
            guard let item = child as? ListItem else { continue }
            counter += 1
            let id = counter
            result.append(
                PreviewListItem(
                    id: id,
                    isChecked: item.checkbox.map { $0 == .checked },
                    blocks: blocks(in: item)
                )
            )
        }
        return result
    }

    private func previewTable(_ table: Markdown.Table) -> PreviewTable {
        let alignments = table.columnAlignments.map { alignment -> PreviewColumnAlignment in
            switch alignment {
            case .center: return .center
            case .right: return .trailing
            default: return .leading
            }
        }
        return PreviewTable(
            alignments: alignments,
            header: table.head.cells.map { inlineText($0) },
            rows: table.body.rows.map { row in row.cells.map { inlineText($0) } }
        )
    }

    // MARK: インライン

    /// ブロック1つ分のインライン要素を、表示用の `AttributedString` にする。
    private func inlineText(_ markup: Markup) -> AttributedString {
        var result = inline(markup)
        linkifyBareURLs(in: &result)
        return result
    }

    /// インライン要素を `AttributedString` に畳む。
    ///
    /// 意味づけは `inlinePresentationIntent` に載せるが、SwiftUI の `Text` が
    /// 実際に描いてくれるのは強調と強い強調だけ。取り消し線と等幅は
    /// 具体的な属性も併せて指定しないと見た目に出ない。
    private func inline(_ markup: Markup, intent: InlinePresentationIntent = []) -> AttributedString {
        var result = AttributedString()
        for child in markup.children {
            result.append(inlineFragment(child, intent: intent))
        }
        return result
    }

    private func inlineFragment(_ markup: Markup, intent: InlinePresentationIntent) -> AttributedString {
        func styled(_ string: String, adding extra: InlinePresentationIntent = []) -> AttributedString {
            var fragment = AttributedString(string)
            let combined = intent.union(extra)
            if !combined.isEmpty {
                fragment.inlinePresentationIntent = combined
            }
            if combined.contains(.strikethrough) {
                fragment.strikethroughStyle = Text.LineStyle.single
            }
            if combined.contains(.code) {
                // 書体の意匠だけを差し替える属性は AttributedString に無いので、
                // フォントごと指定する。テーマの文字サイズをここで焼き込むため、
                // 文字サイズが変わったら組み直しが要る（`MarkdownPreview` 側で対応）。
                fragment.font = .system(size: theme.fontSize, design: .monospaced)
                fragment.foregroundColor = Color(platform: theme.code)
            }
            return fragment
        }

        switch markup {
        case let text as Markdown.Text:
            return styled(text.string)

        case is Emphasis:
            return inline(markup, intent: intent.union(.emphasized))

        case is Strong:
            return inline(markup, intent: intent.union(.stronglyEmphasized))

        case is Strikethrough:
            return inline(markup, intent: intent.union(.strikethrough))

        case let code as InlineCode:
            return styled(code.code, adding: .code)

        case let link as Markdown.Link:
            var fragment = inline(link, intent: intent)
            if let destination = link.destination, let url = URL(string: destination) {
                fragment.link = url
                // クリックできることを示す。SwiftUI の Text はリンク単位のホバーを
                // 扱えないため（`docs/02-decision-log.md` の D-13）、常に下線を引く。
                // エディタ側で URL に下線を引いているのとも揃う。
                fragment.underlineStyle = Text.LineStyle.single
            }
            return fragment

        case let image as Markdown.Image:
            // 画像は描かない。代替テキストがあればそれを見せる。
            let alt = image.plainText.isEmpty ? (image.source ?? "image") : image.plainText
            return styled("🖼 \(alt)", adding: .emphasized)

        case is SoftBreak:
            return styled(" ")

        case is LineBreak:
            return styled("\n")

        case let html as InlineHTML:
            return styled(html.rawHTML, adding: .code)

        default:
            guard markup.childCount > 0 else { return styled(markup.format()) }
            return inline(markup, intent: intent)
        }
    }

    // MARK: 裸の URL

    private static let linkDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    /// 山括弧の無い URL・メールアドレスにリンクを張る。
    ///
    /// swift-markdown は GFM の `table` / `strikethrough` / `tasklist` は有効にしているが、
    /// `autolink` 拡張は有効にしていない。`MarkdownCore` は裸の URL をリンクとして
    /// 着色するので、補わないとエディタとプレビューで見え方がずれる。
    ///
    /// `NSDataDetector` は GFM より貪欲（`example.com` 単体も拾う）なので、
    /// `MarkdownCore` と同じ条件まで絞り込む。
    private func linkifyBareURLs(in text: inout AttributedString) {
        guard let linkDetector = Self.linkDetector else { return }
        let plain = String(text.characters)
        guard !plain.isEmpty else { return }

        let matches = linkDetector.matches(
            in: plain,
            range: NSRange(plain.startIndex..<plain.endIndex, in: plain)
        )

        for match in matches {
            guard let url = match.url,
                  let stringRange = Range(match.range, in: plain),
                  Self.isGFMAutolink(String(plain[stringRange]))
            else { continue }

            let lowerOffset = plain.distance(from: plain.startIndex, to: stringRange.lowerBound)
            let upperOffset = plain.distance(from: plain.startIndex, to: stringRange.upperBound)
            let characters = text.characters
            let lower = characters.index(characters.startIndex, offsetBy: lowerOffset)
            let upper = characters.index(characters.startIndex, offsetBy: upperOffset)
            let range = lower..<upper

            // 既にリンクが張られている、あるいはコードの中なら触らない。
            let alreadyHandled = text[range].runs.contains {
                $0.link != nil || $0.inlinePresentationIntent?.contains(.code) == true
            }
            guard !alreadyHandled else { continue }

            text[range].link = url
            text[range].underlineStyle = Text.LineStyle.single
        }
    }

    private static func isGFMAutolink(_ candidate: String) -> Bool {
        let lowercased = candidate.lowercased()
        return lowercased.hasPrefix("http://")
            || lowercased.hasPrefix("https://")
            || lowercased.hasPrefix("www.")
            || candidate.contains("@")
    }
}
