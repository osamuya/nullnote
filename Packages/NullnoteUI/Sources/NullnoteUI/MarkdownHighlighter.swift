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

    public init(theme: MarkdownTheme) {
        self.theme = theme
    }

    /// 属性を貼り直す。既存の属性は捨ててから貼る。
    ///
    /// - Parameters:
    ///   - storage: 対象。`NSTextStorage` をそのまま渡せる。
    ///   - text: `storage.string` と同じ内容。呼び出し側が既に持っている `String` を
    ///     使い回して、`NSString` からの変換を1回に抑えるために外から渡す。
    public func apply(to storage: NSMutableAttributedString, text: String) {
        let fullRange = NSRange(location: 0, length: storage.length)

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(baseAttributes, range: fullRange)

        // トークンの範囲は String.Index。UTF-16 のオフセットへ直すのに毎回
        // 文字列の先頭から数えると O(文字数 × トークン数) になる。
        // 行の先頭までの距離を累積しておき、各トークンは行頭からの距離だけ測る。
        let lines = tokenizer.tokenizeLines(text)
        var lineStartUTF16 = 0

        // フェンス付きコードブロックの言語と、行をまたぐブロックコメントの状態。
        var codeLanguage: CodeSyntax.Language?
        var codeState = CodeSyntax.State()

        for (offset, line) in lines.enumerated() {
            let lineStart = line.range.lowerBound
            let headingLevel = line.headingLevel

            // ```swift の swift を拾って、以降の行の色分けに使う。
            for token in line.tokens where token.kind == .codeLanguage {
                codeLanguage = CodeSyntax.language(named: String(text[token.range]))
                codeState = CodeSyntax.State()
            }

            func nsRange(_ range: Range<String.Index>) -> NSRange? {
                let location = lineStartUTF16 + text.utf16.distance(from: lineStart, to: range.lowerBound)
                let length = text.utf16.distance(from: range.lowerBound, to: range.upperBound)
                guard length > 0, location >= 0, location + length <= storage.length else { return nil }
                return NSRange(location: location, length: length)
            }

            for token in line.tokens {
                guard let range = nsRange(token.range) else { continue }
                apply(token.kind, to: storage, range: range, headingLevel: headingLevel)

                // コードブロックの中だけ、さらに簡易ハイライトを重ねる。
                if token.kind == .codeBlock, let language = codeLanguage {
                    let result = CodeSyntax.tokenize(
                        text, range: token.range, language: language, state: codeState
                    )
                    codeState = result.stateAfter
                    for code in result.tokens {
                        guard let codeRange = nsRange(code.range) else { continue }
                        storage.addAttribute(.foregroundColor, value: color(for: code.kind), range: codeRange)
                    }
                }
            }

            // フェンスを抜けたら言語の指定も終わり。
            if case .fencedCode = line.stateAfter {} else {
                codeLanguage = nil
                codeState = CodeSyntax.State()
            }

            let nextLineStart = offset + 1 < lines.count ? lines[offset + 1].range.lowerBound : text.endIndex
            lineStartUTF16 += text.utf16.distance(from: lineStart, to: nextLineStart)
        }
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
