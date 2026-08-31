import Foundation
import MarkdownCore

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// `MarkdownCore` のトークン列を、テキストビューが描ける属性に変換する。
///
/// 色やフォントを決めるのはここだけ。`MarkdownCore` は範囲と種別しか知らない。
public struct MarkdownHighlighter {

    public var theme: MarkdownTheme
    private let tokenizer = MarkdownTokenizer()

    /// 前回貼ったときの、行ごとの状態。**差分更新の打ち切り位置を決めるためだけに持つ。**
    private var signatures: [LineSignature] = []

    /// その行の見た目を決めているすべて（行の中身を除く）。
    ///
    /// 編集した行より後ろで、これが前回と一致した行が見つかれば、
    /// そこから先のトークンは前回と同じ。貼り直さなくてよい。
    private struct LineSignature: Equatable {
        /// この行を処理し終えた時点のブロック状態。
        let block: MarkdownBlockState
        /// 開いているフェンスの言語名。`Language` は比較できないので名前で持つ。
        let language: String?
        /// 行をまたぐブロックコメントの状態。
        let code: CodeSyntax.State
    }

    public init(theme: MarkdownTheme) {
        self.theme = theme
    }

    /// 属性を貼り直す。
    ///
    /// - Parameters:
    ///   - storage: 対象。`NSTextStorage` をそのまま渡せる。
    ///   - text: `storage.string` と同じ内容。呼び出し側が既に持っている `String` を
    ///     使い回して、`NSString` からの変換を1回に抑えるために外から渡す。
    ///   - edited: 直前の編集で書き換わった、**いまの本文での** UTF-16 範囲。
    ///     渡すと、その周辺の行だけ貼り直す。`nil` なら全文を貼り直す
    ///     （初回、テーマ変更、外から本文が差し替わったとき）。
    ///
    /// 全文を貼り直すと、`NSTextStorage` は文書全体のレイアウトを捨てる。
    /// 1.5万文字で 27.6 ms（うち組み直しが 17.2 ms）かかり、打鍵ごとには重すぎた。
    public mutating func apply(
        to storage: NSMutableAttributedString,
        text: String,
        edited: NSRange? = nil
    ) {
        // トークンの範囲は String.Index。UTF-16 のオフセットへ直すのに毎回
        // 文字列の先頭から数えると O(文字数 × トークン数) になる。
        // 行の先頭までの距離を累積しておき、各トークンは行頭からの距離だけ測る。
        let lines = tokenizer.tokenizeLines(text)
        let extents = lineExtents(of: lines, in: text)
        let previous = signatures
        // 行数がずれたぶん。前回の何行目と比べるかを決めるのに使う。
        let lineDelta = lines.count - previous.count

        // 貼り直す範囲。編集した行の**1行手前**から始める。
        // 表のヘッダ行は「次の行が区切り行か」で決まるので、
        // ある行を直すと1行手前の見え方が変わることがある。
        var repaintFrom = 0
        var editedThrough = lines.count - 1
        if let edited, !previous.isEmpty {
            let first = lineIndex(containing: edited.location, in: extents)
            let last = lineIndex(containing: edited.location + edited.length, in: extents)
            repaintFrom = max(0, first - 1)
            editedThrough = last
        }

        storage.beginEditing()
        defer { storage.endEditing() }

        // フェンス付きコードブロックの言語と、行をまたぐブロックコメントの状態。
        var codeLanguage: CodeSyntax.Language?
        var codeLanguageName: String?
        var codeState = CodeSyntax.State()

        var newSignatures: [LineSignature] = []
        newSignatures.reserveCapacity(lines.count)
        var converged = false

        for (offset, line) in lines.enumerated() {
            let lineStart = line.range.lowerBound
            let headingLevel = line.headingLevel
            let extent = extents[offset]

            // ```swift の swift を拾って、以降の行の色分けに使う。
            for token in line.tokens where token.kind == .codeLanguage {
                codeLanguageName = String(text[token.range])
                codeLanguage = CodeSyntax.language(named: codeLanguageName ?? "")
                codeState = CodeSyntax.State()
            }

            // 貼るかどうかに関わらず、状態は全行ぶん進める。
            // 途中の行を飛ばすと、後ろの行の色が狂う。
            let repainting = !converged && offset >= repaintFrom

            func nsRange(_ range: Range<String.Index>) -> NSRange? {
                let location = extent.location + text.utf16.distance(from: lineStart, to: range.lowerBound)
                let length = text.utf16.distance(from: range.lowerBound, to: range.upperBound)
                guard length > 0, location >= 0, location + length <= storage.length else { return nil }
                return NSRange(location: location, length: length)
            }

            if repainting, extent.length > 0, extent.location + extent.length <= storage.length {
                storage.setAttributes(baseAttributes, range: extent)
            }

            for token in line.tokens {
                // コードブロックの中だけ、さらに簡易ハイライトを重ねる。
                // **貼らない行でも状態は進める。**
                var codeResult: CodeSyntax.Result?
                if token.kind == .codeBlock, let language = codeLanguage {
                    let result = CodeSyntax.tokenize(
                        text, range: token.range, language: language, state: codeState
                    )
                    codeState = result.stateAfter
                    codeResult = result
                }

                guard repainting, let range = nsRange(token.range) else { continue }
                apply(token.kind, to: storage, range: range, headingLevel: headingLevel)

                for code in codeResult?.tokens ?? [] {
                    guard let codeRange = nsRange(code.range) else { continue }
                    storage.addAttribute(.foregroundColor, value: color(for: code.kind), range: codeRange)
                }
            }

            // フェンスを抜けたら言語の指定も終わり。
            if case .fencedCode = line.stateAfter {} else {
                codeLanguage = nil
                codeLanguageName = nil
                codeState = CodeSyntax.State()
            }

            let signature = LineSignature(
                block: line.stateAfter, language: codeLanguageName, code: codeState
            )
            newSignatures.append(signature)

            // 編集した行を過ぎたら、状態が前回と一致した時点で打ち切る。
            if !converged, offset > editedThrough {
                let old = offset - lineDelta
                if previous.indices.contains(old), previous[old] == signature {
                    converged = true
                }
            }
        }

        signatures = newSignatures
    }

    /// その行を**打ち始める前**のブロック状態。
    ///
    /// 改行で行頭の印を継ぐかどうかの判断に使う（`LineContinuationRule`）。
    /// コードブロックの中の `- foo` はリストではないので、そこでは継がない。
    ///
    /// `signatures[i]` は「i 行目を処理し終えた時点」なので、
    /// **i 行目の手前は i-1 の値**。まだ塗っていない行を聞かれたら `.blank` を返す。
    public func blockState(beforeLine line: Int) -> MarkdownBlockState {
        guard line > 0, signatures.indices.contains(line - 1) else { return .blank }
        return signatures[line - 1].block
    }

    /// 各行の UTF-16 範囲（改行を含む）。
    private func lineExtents(of lines: [MarkdownLineTokens], in text: String) -> [NSRange] {
        var result: [NSRange] = []
        result.reserveCapacity(lines.count)
        var location = 0
        for (offset, line) in lines.enumerated() {
            let nextStart = offset + 1 < lines.count ? lines[offset + 1].range.lowerBound : text.endIndex
            let length = text.utf16.distance(from: line.range.lowerBound, to: nextStart)
            result.append(NSRange(location: location, length: length))
            location += length
        }
        return result
    }

    /// その位置を含む行。二分探索。
    private func lineIndex(containing location: Int, in extents: [NSRange]) -> Int {
        guard !extents.isEmpty else { return 0 }
        var low = 0
        var high = extents.count - 1
        while low < high {
            let middle = (low + high + 1) / 2
            if extents[middle].location <= location { low = middle } else { high = middle - 1 }
        }
        return low
    }

    private func color(for kind: CodeSyntax.Kind) -> PlatformColor {
        switch kind {
        case .keyword: theme.codeKeyword
        case .string: theme.codeString
        case .comment: theme.codeComment
        case .number: theme.codeNumber
        }
    }

    // MARK: - 基本の属性

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = theme.fontSize * 0.25
        paragraph.paragraphSpacing = theme.fontSize * 0.35
        return [
            .font: theme.bodyFont,
            .foregroundColor: theme.text,
            .paragraphStyle: paragraph,
        ]
    }

    // MARK: - 種別ごとの適用

    private func apply(
        _ kind: MarkdownToken.Kind,
        to storage: NSMutableAttributedString,
        range: NSRange,
        headingLevel: Int?
    ) {
        switch kind {
        case .marker(let marker):
            apply(marker, to: storage, range: range, headingLevel: headingLevel)

        case .heading(let level):
            storage.addAttributes([
                .font: PlatformFont
                    .editorBody(size: theme.headingFontSize(level: level))
                    .addingTraits(bold: true),
                .foregroundColor: theme.heading,
            ], range: range)

        case .blockQuote:
            storage.addAttribute(.foregroundColor, value: theme.quote, range: range)
            addTraits(italic: true, to: storage, range: range)

        case .codeBlock:
            // 構文の色を重ねるので、地の色は本文と同じにする。
            // ここをピンクにすると、キーワードや文字列の色が沈んで見える。
            storage.addAttributes([
                .font: theme.monospacedFont,
                .foregroundColor: theme.text,
                .backgroundColor: theme.codeBackground,
            ], range: range)

        case .inlineCode:
            storage.addAttributes([
                .font: theme.monospacedFont,
                .foregroundColor: theme.code,
                .backgroundColor: theme.codeBackground,
            ], range: range)

        case .codeLanguage:
            storage.addAttributes([
                .font: theme.monospacedFont,
                .foregroundColor: theme.marker,
                .backgroundColor: theme.codeBackground,
            ], range: range)

        case .emphasis:
            addTraits(italic: true, to: storage, range: range)

        case .strong:
            addTraits(bold: true, to: storage, range: range)

        case .strikethrough:
            storage.addAttributes([
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: theme.marker,
            ], range: range)

        case .linkText:
            storage.addAttribute(.foregroundColor, value: theme.link, range: range)

        case .linkURL:
            storage.addAttributes([
                .foregroundColor: theme.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)

        case .autolink:
            storage.addAttributes([
                .foregroundColor: theme.link,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ], range: range)

        case .escapedCharacter:
            // 直前のバックスラッシュは薄いが、エスケープされた文字自体は本文の色に戻す。
            storage.addAttribute(.foregroundColor, value: theme.text, range: range)

        case .taskMarker:
            storage.addAttributes([
                .font: theme.monospacedFont.addingTraits(bold: true),
                .foregroundColor: theme.accent,
            ], range: range)

        case .tableHeaderCell:
            addTraits(bold: true, to: storage, range: range)

        case .tableDelimiterCell:
            storage.addAttributes([
                .font: theme.monospacedFont,
                .foregroundColor: theme.marker,
            ], range: range)

        case .tableCell:
            break

        case .htmlComment:
            // プレビューに出ないものなので、本文と同じ濃さで置かない。
            // 記法文字と同じ薄さにして、「効いていない文字」であることを見た目で示す。
            storage.addAttribute(.foregroundColor, value: theme.marker, range: range)

        case .invisibleWhitespace:
            // 文字そのものは描けないので、地を塗って場所を示す。
            storage.addAttribute(
                .backgroundColor, value: theme.invisibleWhitespace, range: range
            )
        }
    }

    private func apply(
        _ marker: MarkdownToken.Marker,
        to storage: NSMutableAttributedString,
        range: NSRange,
        headingLevel: Int?
    ) {
        storage.addAttribute(.foregroundColor, value: theme.marker, range: range)

        switch marker {
        case .heading:
            // 見出し本文と行の高さを揃える。
            storage.addAttribute(
                .font,
                value: PlatformFont.editorBody(size: theme.headingFontSize(level: headingLevel ?? 1)),
                range: range
            )

        case .codeFence, .inlineCode:
            storage.addAttributes([
                .font: theme.monospacedFont,
                .backgroundColor: theme.codeBackground,
            ], range: range)

        case .tablePipe, .thematicBreak:
            storage.addAttribute(.font, value: theme.monospacedFont, range: range)

        case .blockQuote, .list, .emphasis, .strong, .strikethrough,
             .linkBracket, .linkParen, .autolinkAngle, .escape:
            break
        }
    }

    /// 太字・斜体は「足す」。外側のトークンが付けた特性を消さないため。
    private func addTraits(
        bold: Bool = false,
        italic: Bool = false,
        to storage: NSMutableAttributedString,
        range: NSRange
    ) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            guard let font = value as? PlatformFont else { return }
            storage.addAttribute(.font, value: font.addingTraits(bold: bold, italic: italic), range: subrange)
        }
    }
}

extension MarkdownLineTokens {
    /// この行が見出しなら、そのレベル。
    var headingLevel: Int? {
        for token in tokens {
            if case .heading(let level) = token.kind { return level }
        }
        return nil
    }
}
