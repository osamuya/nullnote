import SwiftUI

/// Markdown を整形して表示する読み取り専用のビュー。
///
/// エディタのハイライトとは別のパーサ（swift-markdown）を使う。
/// トークン列はネスト構造を持たないため描画には使えず、逆に描画用の AST は
/// キー入力ごとに回すには重い。役割を分けるのが正しい。
///
/// `anchorLine` を渡すと、その行を含むブロックが画面の上端に来るよう追従する。
/// エディタ側の `MarkdownEditorView(topVisibleLine:)` と組にして使う。
public struct MarkdownPreview: View {

    private let source: String
    private let theme: MarkdownTheme
    /// エディタで一番上に見えている行。ここに対応するブロックへ追従する。
    private let anchorLine: Int?
    /// 文書のファイル。画像の相対パスの基準にする。
    private let documentURL: URL?
    /// 普通の改行を、そのまま改行として描くか（設定で切り替える。D-33）。
    private let breaksOnNewline: Bool

    @State private var blocks: [PreviewBlock] = []

    public init(
        source: String,
        theme: MarkdownTheme,
        anchorLine: Int? = nil,
        documentURL: URL? = nil,
        breaksOnNewline: Bool = false
    ) {
        self.source = source
        self.theme = theme
        self.anchorLine = anchorLine
        self.documentURL = documentURL
        self.breaksOnNewline = breaksOnNewline
    }

    private static let horizontalPadding: CGFloat = 20

    public var body: some View {
        // 幅を明示的に測って渡す。
        // `HSplitView` は子に確定した幅を提案しないことがあり、
        // AppKit のテキストビューが「折り返さない自然な幅」で配置されて切れてしまう。
        GeometryReader { geometry in
        ScrollViewReader { proxy in
            ScrollView {
                // 間隔はブロックの組で決める（`PreviewSpacing`）。
                // `VStack(spacing:)` の一律の値だと、見出しの前も段落どうしも同じになる。
                //
                // **見えているところだけ組む。** ブロックはどれも `NSTextView` を持ち、
                // 表はマスの数だけ持つ。全部を先に組むと、表20個の文書で 1341 枚になり、
                // 開くのに 1290 ms かかっていた（release 実測）。
                // 画面ぶんだけなら 135 枚・218 ms。費用が「開くとき」から
                // 「スクロールするとき」へ移り、どちらも待てる長さに収まる。
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        PreviewBlockView(block: block, theme: theme, documentURL: documentURL).erased
                            .padding(.top, PreviewSpacing.gap(
                                before: block,
                                after: index > 0 ? blocks[index - 1] : nil,
                                fontSize: theme.fontSize
                            ))
                    }
                }
                .frame(
                    width: max(0, geometry.size.width - Self.horizontalPadding * 2),
                    alignment: .leading
                )
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 18)
                .textSelection(.enabled)
                // 拡大表示は段落をまたいで送れる。文書ぜんぶの画像を配る。
                .environment(\.previewImageList, blocks.allImages)
            }
            .onChange(of: anchorLine) { _, line in
                scroll(to: line, using: proxy)
            }
            .onChange(of: blocks.count) { _, _ in
                // 解析し直した直後は id が振り直されるので、位置を取り直す。
                scroll(to: anchorLine, using: proxy)
            }
        }
        }
        .background(Color(platform: theme.background))
        .markdownColorScheme(theme.appearance)
        // インラインコードのフォントと色は解析時に焼き込まれるので、
        // 文字サイズや外観が変わったときも組み直す。
        .task(id: ReloadKey(theme: theme, source: source, breaksOnNewline: breaksOnNewline)) {
            await reload()
        }
    }

    /// 指定した行を含むブロックを画面上端に合わせる。
    ///
    /// ブロック単位でしか合わせられないので、段落の途中までスクロールしても
    /// プレビューはその段落の先頭で止まる。行の高さがエディタとプレビューで
    /// 違う以上、比率で合わせるとかえって大きくずれるため、こちらを採る。
    private func scroll(to line: Int?, using proxy: ScrollViewProxy) {
        guard let line, let id = blockID(containing: line) else { return }
        proxy.scrollTo(id, anchor: .top)
    }

    private func blockID(containing line: Int) -> Int? {
        blocks.blockID(containing: line)
    }

    private struct ReloadKey: Hashable {
        let source: String
        let fontSize: CGFloat
        let appearance: MarkdownAppearance
        /// 改行の扱いも解析時に畳み込むので、切り替えたら組み直す。
        let breaksOnNewline: Bool

        init(theme: MarkdownTheme, source: String, breaksOnNewline: Bool) {
            self.source = source
            self.fontSize = theme.fontSize
            self.appearance = theme.appearance
            self.breaksOnNewline = breaksOnNewline
        }
    }

    /// 入力が止まってから解析する。
    ///
    /// 解析コストは文書サイズに比例し、5万文字で 45 ms ほどかかる（release ビルド実測）。
    /// 1フレーム 16.7 ms を超えるので、打鍵ごとに走らせるとプレビュー側が引っかかる。
    /// `task(id:)` は `source` が変わると前のタスクを取り消すため、
    /// 先頭で待つだけで打ち終わるまで解析が始まらない。
    private func reload() async {
        if !blocks.isEmpty {
            // 初回だけは待たずに出す。2回目以降が打鍵中の更新。
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
        }
        blocks = PreviewBuilder.build(source, theme: theme, breaksOnNewline: breaksOnNewline)
    }
}

// MARK: - ブロックの間隔

/// ブロックとブロックのあいだに空ける量。
///
/// **一律にしない。** 段落どうしと、見出しの前と、表やコードの前では、
/// 必要な間隔が違う。詰まっていると、どこまでが一続きの話なのか分からなくなる。
///
/// 決め方は「前のブロックが**下に**求める量」と「次のブロックが**上に**求める量」の
/// 大きい方。足し算にすると、重いブロックが続いたときに空きすぎる。
enum PreviewSpacing {

    /// 文字サイズに対する倍率。`14pt` のときの実寸を併記する。
    private struct Margin {
        let top: CGFloat
        let bottom: CGFloat
    }

    private static func margin(of block: PreviewBlock) -> Margin {
        switch block.content {
        case .heading(let level, _):
            // 見出しは前の話の区切り。上を大きく空け、下は本文と近づける。
            level <= 2
                ? Margin(top: 2.4, bottom: 1.1)     // 33.6pt / 15.4pt
                : Margin(top: 1.9, bottom: 1.1)     // 26.6pt / 15.4pt

        case .paragraph:
            Margin(top: 0.85, bottom: 0.85)         // 11.9pt

        case .codeBlock, .table, .list, .quote, .images, .thematicBreak:
            // 地の色や罫線を持つ塊。本文と同じ間隔だと貼り付いて見える。
            //
            // **差を付けすぎるくらいでちょうどよい。** 行そのものが持つ行間が
            // 常に足されるので、指定の差はそのままの見え方にはならない
            // （0.85 と 1.3 では、実測で 3pt しか違わなかった）。
            Margin(top: 1.6, bottom: 1.6)           // 22.4pt
        }
    }

    /// `block` の上に空ける量。`previous` は直前のブロック（先頭なら nil）。
    static func gap(before block: PreviewBlock, after previous: PreviewBlock?, fontSize: CGFloat) -> CGFloat {
        // 先頭は外周の余白に任せる。
        guard let previous else { return 0 }
        return max(margin(of: previous).bottom, margin(of: block).top) * fontSize
    }
}

// MARK: - ブロック

private struct PreviewBlockView: View {

    let block: PreviewBlock
    let theme: MarkdownTheme
    /// 画像の相対パスの基準。
    var documentURL: URL?
    /// 引用の中など、本文と違う色で描きたいときに引き継ぐ。
    /// AppKit のテキストビューは SwiftUI の `foregroundStyle` を受け取らないため、
    /// 色は明示的に渡す必要がある。
    var textColor: PlatformColor?

    var body: some View {
        switch block.content {
        case .heading(let level, let text):
            PreviewText(
                text, theme: theme,
                font: .editorBody(size: theme.headingFontSize(level: level)).addingTraits(bold: true),
                color: theme.heading
            )

        case .paragraph(let text):
            PreviewText(text, theme: theme, color: textColor)

        case .quote(let blocks):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(platform: theme.marker))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: theme.fontSize * 0.5) {
                    ForEach(blocks) {
                        PreviewBlockView(
                            block: $0, theme: theme, documentURL: documentURL, textColor: theme.quote
                        ).erased
                    }
                }
                .foregroundStyle(Color(platform: theme.quote))
                .padding(.leading, 12)
            }

        case .list(let list):
            PreviewListView(list: list, theme: theme, documentURL: documentURL, textColor: textColor)

        case .codeBlock(let code, let language):
            PreviewCodeBlockView(code: code, language: language, theme: theme)

        case .table(let table):
            PreviewTableView(table: table, theme: theme)

        case .images(let images):
            PreviewImagesView(images: images, theme: theme, documentURL: documentURL)

        case .thematicBreak:
            Divider().overlay(Color(platform: theme.marker))
        }
    }

    /// 再帰する箇所で型が無限に育つのを避ける。
    var erased: AnyView { AnyView(self) }
}

// MARK: - リスト

private struct PreviewListView: View {

    let list: PreviewList
    let theme: MarkdownTheme
    var documentURL: URL?
    var textColor: PlatformColor?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.fontSize * 0.4) {
            ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(for: item, at: index)
                    VStack(alignment: .leading, spacing: theme.fontSize * 0.4) {
                        ForEach(item.blocks) {
                            PreviewBlockView(block: $0, theme: theme, textColor: textColor).erased
                        }
                    }
                    // AppKit のテキストビューは「折り返さない自然な幅」を理想の幅として返す。
                    // 指定しないと HStack が幅を配分しきれず、本文だけ狭く折り返される。
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.leading, 4)
    }

    @ViewBuilder
    private func marker(for item: PreviewListItem, at index: Int) -> some View {
        if let isChecked = item.isChecked {
            if isChecked {
                // `checkmark.square.fill` はチェック部分を塗らずに背景を透かすため、
                // 単色で描くとダークテーマでチェックマークが暗く沈む。
                // palette で「チェック＝白 / 箱＝accent」と塗り分け、
                // どちらのテーマでも白いチェックにする。
                Image(systemName: "checkmark.square.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color(platform: theme.accent))
                    .font(.system(size: theme.fontSize))
            } else {
                Image(systemName: "square")
                    .foregroundStyle(Color(platform: theme.marker))
                    .font(.system(size: theme.fontSize))
            }
        } else if list.isOrdered {
            Text("\(list.start + index).")
                .font(.system(size: theme.fontSize, design: .monospaced))
                .foregroundStyle(Color(platform: theme.marker))
        } else {
            Text("•")
                .font(.system(size: theme.fontSize))
                .foregroundStyle(Color(platform: theme.marker))
        }
    }
}

// MARK: - コードブロック

private struct PreviewCodeBlockView: View {

    let code: String
    let language: String?
    let theme: MarkdownTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.system(size: theme.fontSize * 0.8, design: .monospaced))
                    .foregroundStyle(Color(platform: theme.marker))
            }
            Text(highlighted)
                .font(.system(size: theme.fontSize, design: .monospaced))
                .foregroundStyle(Color(platform: theme.text))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(platform: theme.codeBackground))
        )
    }

    /// エディタ側と同じ規則で、キーワード・文字列・コメント・数値だけ色を付ける。
    private var highlighted: AttributedString {
        var result = AttributedString(code)
        guard let language = CodeSyntax.language(named: language) else { return result }

        var state = CodeSyntax.State()
        let characters = result.characters

        // 行ごとに走査する。ブロックコメントの状態だけ次の行へ引き継ぐ。
        var lineStart = code.startIndex
        while lineStart <= code.endIndex {
            let lineEnd = code[lineStart...].firstIndex(where: \.isNewline) ?? code.endIndex
            let outcome = CodeSyntax.tokenize(
                code, range: lineStart..<lineEnd, language: language, state: state
            )
            state = outcome.stateAfter

            for token in outcome.tokens {
                let lower = code.distance(from: code.startIndex, to: token.range.lowerBound)
                let upper = code.distance(from: code.startIndex, to: token.range.upperBound)
                let from = characters.index(characters.startIndex, offsetBy: lower)
                let to = characters.index(characters.startIndex, offsetBy: upper)
                result[from..<to].foregroundColor = Color(platform: color(for: token.kind))
            }

            guard lineEnd < code.endIndex else { break }
            lineStart = code.index(after: lineEnd)
        }
        return result
    }

    private func color(for kind: CodeSyntax.Kind) -> PlatformColor {
        switch kind {
        case .keyword: theme.codeKeyword
        case .string: theme.codeString
        case .comment: theme.codeComment
        case .number: theme.codeNumber
        }
    }
}

// MARK: - 表

private struct PreviewTableView: View {

    let table: PreviewTable
    let theme: MarkdownTheme

    /// 罫線の太さ。マス目の隙間と外周に、この幅だけ下地の色を見せる。
    private static let border: CGFloat = 1

    var body: some View {
        // 列が多いと横にはみ出すので、表だけ横スクロールさせる。
        ScrollView(.horizontal, showsIndicators: false) {
            // マス目のあいだを `border` だけ空け、下地に罫線の色を敷く。
            // 各マスは不透明なので、空けたぶんだけが線として見える。
            // 線を1本ずつ引くより、太さと交点のずれが出にくい。
            Grid(alignment: .topLeading, horizontalSpacing: Self.border, verticalSpacing: Self.border) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        cellView(
                            cell,
                            column: column,
                            font: theme.bodyFont.addingTraits(bold: true),
                            fill: theme.tableHeaderBackground
                        )
                    }
                }
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            cellView(cell, column: column, font: theme.bodyFont, fill: theme.background)
                        }
                    }
                }
            }
            .font(.system(size: theme.fontSize))
            .foregroundStyle(Color(platform: theme.text))
            // 外周ぶんの下地。
            .padding(Self.border)
            .background(Color(platform: theme.tableBorder))
        }
    }

    private func cellView(
        _ cell: AttributedString,
        column: Int,
        font: PlatformFont,
        fill: PlatformColor
    ) -> some View {
        // 揃えは文字列側（段落スタイル）で行う。
        // テキストビューは提案された幅いっぱいに広がるので、
        // 外側の `frame(alignment:)` では効かない。
        PreviewText(cell, theme: theme, font: font, alignment: alignment(of: column))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            // **縦にも広げること。** `Grid` は行の高さを一番高いマスに合わせるが、
            // マスの方を引き伸ばしはしない。背の低いマス（空のマスや、
            // 隣が折り返して2行になった行）の下に下地の罫線色がそのまま出る。
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(platform: fill))
    }

    private func alignment(of column: Int) -> TextAlignment {
        guard column < table.alignments.count else { return .leading }
        switch table.alignments[column] {
        case .center: return .center
        case .trailing: return .trailing
        case .leading: return .leading
        }
    }
}
