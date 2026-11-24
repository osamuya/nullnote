import Foundation
import Markdown
import MarkdownCore
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
        /// ```` ```mermaid ```` で囲まれた図。**中身は解釈しない。**
        ///
        /// 記述の解釈と作図は mermaid.js に任せ、ここでは素通しする。
        /// 自前で解釈すると「Nullnote が描けるもの」と「mermaid が描けるもの」が
        /// 永久にずれ続け、そのずれを説明し続けることになる（D-65）。
        case mermaid(code: String)
        case table(PreviewTable)
        /// 絵として置く画像。段落に文字が混ざっていたら、文字はその前後の別の段落になる（D-76）。
        ///
        /// 1枚とは限らない。間に文字を挟まずに続けて書かれた画像は、1つのまとまりにする。
        /// リンクで包んだ画像は含めない（そちらは代替テキストのまま）。
        case images([PreviewImageRef])
        case thematicBreak
        /// 合流の印で割られたところ。**Markdown の記法ではない。**
        ///
        /// 印をそのまま解釈させると `=======` が下線見出しになり、
        /// `>>>>>>>` が7重の引用になる。**周りの本文の意味まで変わる**ので、
        /// 解釈させる前に切り分けて、印は印として見せる（D-60）。
        case conflict(PreviewConflict)
    }
}

/// 合流の印で割られたところ。中身はどちらも Markdown として組んである。
struct PreviewConflict {
    /// 自分の版の中身。**空のこともある**（外だけが書き足した場合）。
    let ours: [PreviewBlock]
    /// 外の版の中身。
    let theirs: [PreviewBlock]
}

/// 絵として置く画像1枚ぶん。
struct PreviewImageRef: Identifiable {
    let id: Int
    /// `![]()` に書かれた場所。解釈は描く側（`ImageSourceResolver`）に任せる。
    let source: String
    let alt: String
    let layout: PreviewImageLayout
}

/// 画像の置き方。`![]()` の直後の `{.…}` で指定する。
///
/// **Markdown の標準ではない。** 他のツールでは `{.center}` の文字がそのまま見える。
/// 見た目の指定を本文に持ち込む以上、この割り切りは避けられない。
enum PreviewImageLayout: String {
    /// 指定なし。元の大きさまでで、左に置く。
    case normal
    /// 幅いっぱいに広げて中央に置く。
    case center
    /// 小さな正方形に切って並べる。押すと大きく開く。
    case thumbnail
    /// 与えられた場所に収まるだけ広げる。**拡大表示の中だけで使う。**
    /// `{.fitted}` と書いても効かない（`init(marker:)` が返さない）。
    case fitted

    /// `{.center}` のような書き方から読む。知らない名前は指定なし扱い。
    init(marker: String) {
        switch marker {
        case "center": self = .center
        case "thumbnail": self = .thumbnail
        // 知らない名前は指定なし扱い。あとで種類を増やしても古い文書が壊れない。
        default: self = .normal
        }
    }
}

extension Array where Element == PreviewBlock {
    /// 文書に出てくる画像を、書かれている順に集める。
    ///
    /// 拡大表示の前後送りは**段落をまたぐ**ので、段落ごとではなく文書全体で持つ。
    /// 引用やリストの中に入っているものも拾う。
    var allImages: [PreviewImageRef] {
        flatMap { block -> [PreviewImageRef] in
            switch block.content {
            case .images(let images): images
            case .quote(let blocks): blocks.allImages
            case .list(let list): list.items.flatMap { $0.blocks.allImages }
            case .conflict(let conflict): conflict.ours.allImages + conflict.theirs.allImages
            default: []
            }
        }
    }

    /// 文書のどこかに mermaid の図があるか。**引用やリストの中も見る。**
    ///
    /// プレビューの積み方を決めるのに使う。図があるときは `LazyVStack` を使えない
    /// （高さが遅れて決まるため、送れる範囲が足りなくなる。D-65）。
    var containsDiagram: Bool {
        contains { block in
            switch block.content {
            case .mermaid: true
            case .quote(let blocks): blocks.containsDiagram
            case .list(let list): list.items.contains { $0.blocks.containsDiagram }
            case .conflict(let conflict):
                conflict.ours.containsDiagram || conflict.theirs.containsDiagram
            default: false
            }
        }
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
    /// 普通の改行（行末に半角スペース2つが無いもの）をどう読むか（D-33・D-74）。
    /// 既定は CommonMark どおり、ひと続きの行として畳む。
    private let newlineStyle: NewlineStyle
    private var counter = 0
    /// 行番号を持たないノードに与える値。直前に分かっている行を引き継ぐ。
    private var lastKnownLine = 1
    /// いま組んでいる断片が、元の本文の何行目から始まるか（0 始まり）。
    ///
    /// 合流の印で本文を切って組むので、`swift-markdown` が返す行番号は
    /// 断片の中の位置でしかない。**元の本文の行に直す**ために足す。
    /// エディタとのスクロール同期がここに乗っている。
    private var lineOffset = 0
    /// 本文。プレビューの文字が本文のどこから来たかを確かめるのに使う（#M0045）。
    private let source: NSString
    private let positions: SourcePositionConverter

    private init(theme: MarkdownTheme, newlineStyle: NewlineStyle, source: String) {
        self.theme = theme
        self.newlineStyle = newlineStyle
        self.source = source as NSString
        self.positions = SourcePositionConverter(source)
    }

    static func build(
        _ source: String,
        theme: MarkdownTheme,
        newlineStyle: NewlineStyle = .markdown
    ) -> [PreviewBlock] {
        var builder = PreviewBuilder(theme: theme, newlineStyle: newlineStyle, source: source)
        return builder.blocks(splittingConflictsIn: source)
    }

    /// 合流の印で切り分けてから組む。
    ///
    /// **印を `Document(parsing:)` に渡さない。** 渡すと `=======` が下線見出しに、
    /// `>>>>>>>` が7重の引用になり、印の周りの本文まで違う姿で出る（D-60）。
    private mutating func blocks(splittingConflictsIn source: String) -> [PreviewBlock] {
        let regions = ConflictScanner.regions(in: source)
        guard !regions.isEmpty else { return blocks(in: Document(parsing: source)) }

        let lines = source.components(separatedBy: "\n")
        var result: [PreviewBlock] = []
        var cursor = 0
        for region in regions {
            result += blocks(of: lines, in: cursor..<region.ourMarkerLine)

            // 中身は普段どおり組む。プレビューは「どうなるか」を見る場なので、
            // どちらの版も本来の姿で見せる（2026-09-10 に利用者と決めた）。
            let conflict = PreviewConflict(
                ours: blocks(of: lines, in: region.ourBody),
                theirs: blocks(of: lines, in: region.theirBody)
            )
            counter += 1
            result.append(PreviewBlock(
                id: counter,
                sourceLine: region.ourMarkerLine + 1,
                content: .conflict(conflict)
            ))
            cursor = region.theirMarkerLine + 1
        }
        result += blocks(of: lines, in: cursor..<lines.count)
        return result
    }

    /// 与えた行だけを Markdown として組む。行番号は元の本文のものに直す。
    private mutating func blocks(of lines: [String], in range: Range<Int>) -> [PreviewBlock] {
        guard !range.isEmpty else { return [] }
        let outerOffset = lineOffset
        lineOffset = range.lowerBound
        lastKnownLine = range.lowerBound + 1
        let built = blocks(in: Document(parsing: lines[range].joined(separator: "\n")))
        lineOffset = outerOffset
        return built
    }

    // MARK: ブロック

    private mutating func blocks(in markup: Markup) -> [PreviewBlock] {
        // 段落を分けるのは文書の一番外だけ。リスト・引用の中まで分けると、項目の形が崩れる（D-74）。
        let splitsLines = newlineStyle == .paragraph && markup is Document
        return markup.children.flatMap { child -> [PreviewBlock] in
            if let paragraph = child as? Paragraph {
                return splitsLines
                    ? blocks(splittingLinesOf: paragraph)
                    : blocks(splittingImagesOf: Array(paragraph.children))
            }
            return block(from: child).map { [$0] } ?? []
        }
    }

    /// 段落を行ごとに別のブロックにする（「改行で段落を分ける」。D-74）。
    ///
    /// 改行1つで段落を終える書き方（日本語の文章など）では、空行が無いので
    /// 文書がまるごと1つの段落になる。分けないと段落の余白が付かず、
    /// スクロールの追従も段落の頭にしか合わない。
    /// 行末の半角スペース2つの改行も同じく分ける。どちらも段落のつもりで混ざっている。
    ///
    /// 画像だけで出来た段落は、分けずに1つの絵のまとまりのまま（D-27）。
    private mutating func blocks(splittingLinesOf paragraph: Paragraph) -> [PreviewBlock] {
        var lines: [[Markup]] = [[]]
        for child in paragraph.children {
            if child is SoftBreak || child is LineBreak {
                lines.append([])
            } else {
                lines[lines.count - 1].append(child)
            }
        }
        lines.removeAll(where: \.isEmpty)
        let whole = Array(paragraph.children)
        guard lines.count > 1, !Self.isImagesOnly(whole) else {
            return blocks(splittingImagesOf: whole)
        }
        return lines.flatMap { blocks(splittingImagesOf: $0) }
    }

    /// 段落の中身を、書かれた順に文字のかたまりと絵のかたまりに分けて組む（#019・D-76）。
    ///
    /// 画像の行の次に空行を置かずに文字を書いても、文字と同じ行に画像を書いても、
    /// **画像は絵として出す。** 文字はその前後で別の段落になる。
    /// 続けて書いた画像（間に文字が無いもの）は、1つの絵のまとまりにする（D-27）。
    private mutating func blocks(splittingImagesOf children: [Markup]) -> [PreviewBlock] {
        let pieces = Self.pieces(of: children)
        var result: [PreviewBlock] = []
        for (index, piece) in pieces.enumerated() {
            let first: Markup
            let content: PreviewBlock.Content
            switch piece {
            case .images(let entries):
                first = entries[0].image
                content = .images(entries.map { entry in
                    counter += 1
                    return PreviewImageRef(
                        id: counter, source: entry.image.source ?? "",
                        alt: entry.image.plainText, layout: entry.layout
                    )
                })
            case .text(let nodes):
                first = nodes[0]
                var text = inlineText(nodes)
                // 画像と同じ行に書いた文字は、画像との間の空白が端に残る。
                // 画像の側の端だけを削る（段落の端はもともと cmark が削っている）。
                if index > 0 { Self.trimSpaces(of: &text, leading: true) }
                if index < pieces.count - 1 { Self.trimSpaces(of: &text, leading: false) }
                // コメントを取り除いた結果、何も残らなかった段落は置かない。
                // 空の段落を置くと、そこだけ行間が空いて見える。
                if text.characters.allSatisfy(\.isWhitespace) { continue }
                content = .paragraph(text)
            }
            let line = first.range.map { $0.lowerBound.line + lineOffset } ?? lastKnownLine
            lastKnownLine = line
            counter += 1
            result.append(PreviewBlock(id: counter, sourceLine: line, content: content))
        }
        return result
    }

    /// 段落の中の、文字のかたまりか絵のかたまり。
    enum InlinePiece {
        case text([Markup])
        case images([(image: Markdown.Image, layout: PreviewImageLayout)])
    }

    /// 段落の中身を、書かれた順に文字のかたまりと絵のかたまりに分ける。
    ///
    /// 画像の直後の `{.center}` などは、置き方の指定として読む。
    /// 画像のあいだの空白と改行は、絵のかたまりの中では読み捨てる。
    /// リンクで包んだ画像（`[![](a.png)](…)`）は文字の側に入る（代替テキストのまま）。
    static func pieces(of children: [Markup]) -> [InlinePiece] {
        var result: [InlinePiece] = []
        var text: [Markup] = []
        var images: [(image: Markdown.Image, layout: PreviewImageLayout)] = []

        func flushText() {
            // 画像との境目に来た改行は、どちらのかたまりにも要らない。
            while let first = text.first, first is SoftBreak || first is LineBreak { text.removeFirst() }
            while let last = text.last, last is SoftBreak || last is LineBreak { text.removeLast() }
            if !text.isEmpty { result.append(.text(text)) }
            text = []
        }
        func flushImages() {
            if !images.isEmpty { result.append(.images(images)) }
            images = []
        }

        for child in children {
            switch child {
            case let image as Markdown.Image:
                flushText()
                images.append((image, .normal))
            case is SoftBreak, is LineBreak:
                if images.isEmpty { text.append(child) }
            case let node as Markdown.Text where !images.isEmpty:
                let (layout, rest) = layoutMarker(in: node.string)
                if let layout { images[images.count - 1].layout = layout }
                if rest.allSatisfy(\.isWhitespace) { continue }
                flushImages()
                // 指定を読まなかったときは元のノードのまま渡す（本文の位置を保つため）。
                text.append(layout == nil ? node : Markdown.Text(String(rest)))
            default:
                flushImages()
                text.append(child)
            }
        }
        flushText()
        flushImages()
        return result
    }

    /// 段落が画像だけで出来ているか。空白・改行・置き方の指定は数えない。
    static func isImagesOnly(_ children: [Markup]) -> Bool {
        let pieces = pieces(of: children)
        guard pieces.count == 1, case .images = pieces[0] else { return false }
        return true
    }

    /// 端の半角空白とタブを削る。全角空白は字下げなので残す。
    private static func trimSpaces(of text: inout AttributedString, leading: Bool) {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        if leading {
            while let first = text.characters.first, isSpace(first) {
                text.removeSubrange(text.startIndex..<text.characters.index(after: text.startIndex))
            }
        } else {
            while let last = text.characters.last, isSpace(last) {
                text.removeSubrange(text.characters.index(before: text.endIndex)..<text.endIndex)
            }
        }
    }

    private mutating func block(from markup: Markup) -> PreviewBlock? {
        // 子を辿ると lastKnownLine が進んでしまうので、先に自分の行を控える。
        // **断片の中の行番号なので、元の本文の行に直す。**
        let line = markup.range.map { $0.lowerBound.line + lineOffset } ?? lastKnownLine
        lastKnownLine = line

        guard let content = content(from: markup) else { return nil }
        counter += 1
        return PreviewBlock(id: counter, sourceLine: line, content: content)
    }

    /// 文字列の先頭にある `{.…}` を読む。直前の画像の置き方にする。
    ///
    /// 続けて書かれていたら、最後のものが効く。
    /// - Returns: 読んだ置き方（無ければ nil）と、読み残した文字。
    static func layoutMarker(in text: String) -> (layout: PreviewImageLayout?, rest: Substring) {
        var rest = Substring(text)
        var layout: PreviewImageLayout?
        while true {
            let trimmed = rest.drop(while: \.isWhitespace)
            guard trimmed.hasPrefix("{"), let close = trimmed.firstIndex(of: "}"),
                  trimmed.dropFirst().drop(while: \.isWhitespace).hasPrefix(".")
            else {
                return (layout, rest)
            }
            // `{.center}` `{. center}` `{ .center }` のどれでも読む。
            // 空白ひとつで効かなくなると、なぜ効かないのか分からない。
            let inside = trimmed[trimmed.index(after: trimmed.startIndex)..<close]
            let name = inside
                .trimmingCharacters(in: .whitespaces)
                .drop(while: { $0 == "." })
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            layout = PreviewImageLayout(marker: name)
            rest = trimmed[trimmed.index(after: close)...]
        }
    }

    private mutating func content(from markup: Markup) -> PreviewBlock.Content? {
        switch markup {
        case let heading as Heading:
            return .heading(level: heading.level, text: inlineText(heading))

        case let paragraph as Paragraph:
            // 段落はふつう `blocks(splittingImagesOf:)` で組む。ここに来るのは保険。
            let text = inlineText(paragraph)
            // コメントを取り除いた結果、何も残らなかった段落は置かない。
            // 空の段落を置くと、そこだけ行間が空いて見える。
            if text.characters.allSatisfy(\.isWhitespace) { return nil }
            return .paragraph(text)

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
            if isMermaid(code.language) {
                // **空のときは図にしない。** 書きかけの ```mermaid を開いている最中に、
                // 空の枠が出たり消えたりする。中身が入るまではコードのまま置く。
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return .mermaid(code: body) }
            }
            return .codeBlock(code: body, language: code.language)

        case let table as Markdown.Table:
            return .table(previewTable(table))

        case is ThematicBreak:
            return .thematicBreak

        case let html as HTMLBlock:
            // コメントは**出さない**。下書きのメモや、いったん外した節を
            // 文書に残しておくための書き方なので、見えては意味が無い。
            if isHTMLComment(html.rawHTML) { return nil }
            // それ以外の HTML は解釈せず、そのまま見せる。
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
    /// `<!-- … -->` そのものか。
    ///
    /// **前後に何か付いているものは対象外にする。** CommonMark の HTML ブロックは、
    /// `-->` のあとに書いた文字も同じブロックに含める。そこまで消すと、
    /// 消したつもりのない本文まで見えなくなる。
    private func isHTMLComment(_ rawHTML: String) -> Bool {
        let trimmed = rawHTML.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("<!--") && trimmed.hasSuffix("-->")
    }

    /// 囲みの言語指定が mermaid かどうか。
    ///
    /// cmark は ``` の後ろを丸ごと `language` に入れてくる（`mermaid` のことも
    /// `mermaid theme=dark` のこともある）。GitHub と同じく**最初の語だけ**を見る。
    /// 大文字小文字は区別しない。
    private func isMermaid(_ language: String?) -> Bool {
        guard let language else { return false }
        let first = language.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        return first?.lowercased() == "mermaid"
    }

    private func inlineText(_ markup: Markup) -> AttributedString {
        inlineText(Array(markup.children))
    }

    /// 段落の一部（行ごとに分けたとき）を畳む。
    private func inlineText(_ children: [Markup]) -> AttributedString {
        var result = AttributedString()
        for child in children {
            result.append(inlineFragment(child, intent: []))
        }
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
        func styled(
            _ string: String, adding extra: InlinePresentationIntent = [], source: SourceSpan? = nil
        ) -> AttributedString {
            var fragment = AttributedString(string)
            // 選択を編集画面と行き来させるために、本文のどこから来たかを持たせる。
            fragment[PreviewSourceAttribute.self] = source ?? span(of: markup, rendered: nil)
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

        /// 本文と違うところだけを丸ごと対応させ、前後は1文字ずつ対応させる（#010）。
        func aligned(_ string: String, adding extra: InlinePresentationIntent = []) -> AttributedString {
            guard let whole = span(of: markup, rendered: string) else { return styled(string, adding: extra) }
            guard !whole.isExact else { return styled(string, adding: extra, source: whole) }
            let original = source.substring(with: NSRange(location: whole.start, length: whole.end - whole.start))
            var result = AttributedString()
            for piece in SourceAlignment.pieces(source: original, start: whole.start, rendered: string) {
                result.append(styled(piece.rendered, adding: extra, source: piece.span))
            }
            return result
        }

        switch markup {
        case let text as Markdown.Text:
            return aligned(text.string)

        case is Emphasis:
            return inline(markup, intent: intent.union(.emphasized))

        case is Strong:
            return inline(markup, intent: intent.union(.stronglyEmphasized))

        case is Strikethrough:
            return inline(markup, intent: intent.union(.strikethrough))

        case let code as InlineCode:
            return styled(code.code, adding: .code, source: span(ofCode: code))

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
            // 単なる改行。CommonMark では前後がつながって1行になる。
            // 折り返す・段落を分けるを選んだ人にだけ、書いたとおりの位置で折る（D-33）。
            // 段落を分けるときも、リスト・引用の中はここで折る（D-74）。
            return styled(newlineStyle == .markdown ? " " : "\n")

        case is LineBreak:
            return styled("\n")

        case let html as InlineHTML:
            // 本文の途中に挟んだコメントも出さない。
            if isHTMLComment(html.rawHTML) { return AttributedString() }
            return aligned(html.rawHTML, adding: .code)

        default:
            guard markup.childCount > 0 else { return styled(markup.format()) }
            return inline(markup, intent: intent)
        }
    }

    // MARK: 本文の位置

    /// その要素が本文のどこにあるか。
    ///
    /// - Parameter rendered: プレビューに出す文字。本文のその範囲と同じなら、
    ///   1文字ずつ対応させる。nil か違うときは、範囲を丸ごと対応させる。
    private func span(of markup: Markup, rendered: String?) -> SourceSpan? {
        guard let range = markup.range,
              let start = positions.offset(
                line: range.lowerBound.line + lineOffset, column: range.lowerBound.column),
              let end = positions.offset(
                line: range.upperBound.line + lineOffset, column: range.upperBound.column),
              end >= start, end <= source.length
        else { return nil }

        let exact = rendered.map {
            source.substring(with: NSRange(location: start, length: end - start)) == $0
        } ?? false
        return SourceSpan(start: start, end: end, isExact: exact)
    }

    /// インラインコードの中身が本文のどこにあるか。範囲は前後のバッククォートを含むので、
    /// 中身を探して、そこから1文字ずつ対応させる。
    private func span(ofCode code: InlineCode) -> SourceSpan? {
        guard let whole = span(of: code, rendered: nil) else { return nil }
        let found = source.range(
            of: code.code, range: NSRange(location: whole.start, length: whole.end - whole.start)
        )
        // 中の改行は空白に畳まれるので、見つからないことがある。そのときは丸ごと。
        guard found.location != NSNotFound, !code.code.isEmpty else { return whole }
        return SourceSpan(start: found.location, end: NSMaxRange(found), isExact: true)
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
