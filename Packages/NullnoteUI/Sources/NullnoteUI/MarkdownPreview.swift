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

    @State private var blocks: [PreviewBlock] = []

    public init(source: String, theme: MarkdownTheme, anchorLine: Int? = nil) {
        self.source = source
        self.theme = theme
        self.anchorLine = anchorLine
    }

    private static let horizontalPadding: CGFloat = 20

    public var body: some View {
        // 幅を明示的に測って渡す。
        // `HSplitView` は子に確定した幅を提案しないことがあり、
        // AppKit のテキストビューが「折り返さない自然な幅」で配置されて切れてしまう。
        GeometryReader { geometry in
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: theme.fontSize * 0.85) {
                    ForEach(blocks) { block in
                        PreviewBlockView(block: block, theme: theme).erased
                    }
                }
                .frame(
                    width: max(0, geometry.size.width - Self.horizontalPadding * 2),
                    alignment: .leading
                )
                .padding(.horizontal, Self.horizontalPadding)
                .padding(.vertical, 18)
                .textSelection(.enabled)
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
        .preferredColorScheme(theme.appearance.colorScheme)
        // インラインコードのフォントと色は解析時に焼き込まれるので、
        // 文字サイズや外観が変わったときも組み直す。
        .task(id: ReloadKey(theme: theme, source: source)) { await reload() }
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

        init(theme: MarkdownTheme, source: String) {
            self.source = source
            self.fontSize = theme.fontSize
            self.appearance = theme.appearance
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
        blocks = PreviewBuilder.build(source, theme: theme)
    }
}

// MARK: - ブロック

private struct PreviewBlockView: View {

    let block: PreviewBlock
    let theme: MarkdownTheme
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
            .padding(.top, level <= 2 ? theme.fontSize * 0.4 : 0)

        case .paragraph(let text):
            PreviewText(text, theme: theme, color: textColor)

        case .quote(let blocks):
            HStack(alignment: .top, spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color(platform: theme.marker))
                    .frame(width: 3)
                VStack(alignment: .leading, spacing: theme.fontSize * 0.5) {
                    ForEach(blocks) {
                        PreviewBlockView(block: $0, theme: theme, textColor: theme.quote).erased
                    }
                }
                .foregroundStyle(Color(platform: theme.quote))
                .padding(.leading, 12)
            }

        case .list(let list):
            PreviewListView(list: list, theme: theme, textColor: textColor)

        case .codeBlock(let code, let language):
            PreviewCodeBlockView(code: code, language: language, theme: theme)

        case .table(let table):
            PreviewTableView(table: table, theme: theme)

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

    var body: some View {
        // 列が多いと横にはみ出すので、表だけ横スクロールさせる。
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(table.header.enumerated()), id: \.offset) { column, cell in
                        PreviewText(cell, theme: theme, font: theme.bodyFont.addingTraits(bold: true))
                            .frame(maxWidth: .infinity, alignment: alignment(of: column))
                    }
                }
                Divider().overlay(Color(platform: theme.marker))

                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, cell in
                            PreviewText(cell, theme: theme)
                                .frame(maxWidth: .infinity, alignment: alignment(of: column))
                        }
                    }
                }
            }
            .font(.system(size: theme.fontSize))
            .foregroundStyle(Color(platform: theme.text))
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(platform: theme.marker).opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func alignment(of column: Int) -> Alignment {
        guard column < table.alignments.count else { return .leading }
        switch table.alignments[column] {
        case .center: return .center
        case .trailing: return .trailing
        case .leading: return .leading
        }
    }
}
