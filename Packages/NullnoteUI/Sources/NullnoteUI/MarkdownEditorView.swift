import MarkdownCore
import SwiftUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Markdown を書くためのテキストビュー。
///
/// macOS では `NSTextView`、iOS では `UITextView` を包む。
/// **プラットフォーム差分はこのファイルにだけ置くこと。** ここが漏れ始めると
/// iOS 版が macOS 版の作り直しになる。
/// 「この行へスクロールしてほしい」という依頼。
///
/// 値そのものではなく **依頼が新しく発行されたか** で判定したいので、
/// 同じ行を続けて指しても別の値になるよう `id` を持つ。
public struct EditorScrollRequest: Equatable, Sendable {
    public let line: Int
    private let id = UUID()

    public init(line: Int) {
        self.line = line
    }
}

/// 「この範囲を見えるところまで持ってきてほしい」という依頼。
///
/// 検索で前後のヒットへ送るときに使う。`EditorScrollRequest` と分けてあるのは、
/// あちらが行の先頭を上端に合わせるのに対し、こちらは範囲を画面の中ほどに
/// 置いたうえでカーソルも移すため。同じヒットへ二度送っても効くよう `id` を持つ。
public struct EditorSelectionRequest: Equatable, Sendable {
    public let range: NSRange
    private let id = UUID()

    public init(range: NSRange) {
        self.range = range
    }
}

/// 「入力の焦点を編集画面に戻して」という依頼。
///
/// 検索欄を閉じたときに使う。閉じただけでは焦点が宙に浮き、
/// そのまま打っても本文に入らない。同じ依頼を続けて出しても効くよう `id` を持つ。
public struct EditorFocusRequest: Equatable, Sendable {
    private let id = UUID()
    public init() {}
}

/// 「同じ語を選んで」という依頼。
///
/// メニューから来る。同じ操作を続けて出しても効くよう `id` を持つ。
public struct EditorCommandRequest: Equatable, Sendable {

    public enum Command: Sendable {
        /// カーソルのある語、または次に出てくる同じ語を選びに行く。
        case selectNextOccurrence
        /// 文書中の同じ語を一度に全部選ぶ。
        case selectAllOccurrences
    }

    public let command: Command
    private let id = UUID()

    public init(_ command: Command) {
        self.command = command
    }
}

@MainActor
public struct MarkdownEditorView {

    @Binding var text: String
    var theme: MarkdownTheme
    /// 画面の一番上に見えている行。1 始まり。プレビューとの同期に使う。
    var topVisibleLine: Binding<Int>?
    /// 目次などから「ここへ移動して」と言われたときの依頼。
    var scrollRequest: EditorScrollRequest?
    /// 検索バーから「ここを選んで見せて」と言われたときの依頼。
    var selectionRequest: EditorSelectionRequest?
    /// 検索でヒットした範囲。塗るだけで、移動はさせない。
    var searchHighlight: SearchHighlight?
    /// 「入力の焦点を戻して」という依頼。検索欄を閉じたときに来る。
    var focusRequest: EditorFocusRequest?
    /// 「同じ語を選んで」という依頼。メニューから来る。
    var commandRequest: EditorCommandRequest?
    /// 左端に行番号を出すか。
    var showsLineNumbers: Bool
    /// リストを Tab で深くするときに入れる1段ぶん。
    var indentStyle: IndentStyle
    /// システムの外観が変わったときに再評価させるためだけに読む。
    /// `.system` を実際の外観に解決している以上、OS 側の変化を拾う必要がある。
    @Environment(\.colorScheme) private var systemColorScheme

    public init(
        text: Binding<String>,
        theme: MarkdownTheme,
        topVisibleLine: Binding<Int>? = nil,
        scrollRequest: EditorScrollRequest? = nil,
        selectionRequest: EditorSelectionRequest? = nil,
        searchHighlight: SearchHighlight? = nil,
        focusRequest: EditorFocusRequest? = nil,
        commandRequest: EditorCommandRequest? = nil,
        showsLineNumbers: Bool = false,
        indentStyle: IndentStyle = .fourSpaces
    ) {
        self._text = text
        self.theme = theme
        self.topVisibleLine = topVisibleLine
        self.scrollRequest = scrollRequest
        self.selectionRequest = selectionRequest
        self.searchHighlight = searchHighlight
        self.focusRequest = focusRequest
        self.commandRequest = commandRequest
        self.showsLineNumbers = showsLineNumbers
        self.indentStyle = indentStyle
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, theme: theme, topVisibleLine: topVisibleLine)
    }

    @MainActor
    public final class Coordinator: NSObject {
        var text: Binding<String>
        var topVisibleLine: Binding<Int>?
        var highlighter: MarkdownHighlighter
        /// 最後に適用したテーマ。設定が変わったときだけ貼り直す。
        var appliedFontSize: CGFloat
        #if canImport(AppKit)
        /// 解決したあとの外観で比べる。`.system` のままでも OS 側が変われば貼り直す。
        var appliedAppearanceName: NSAppearance.Name?
        #endif
        /// 本文が変わったときだけ作り直す行の索引。
        private var lineIndex: LineIndex
        /// 最後に報告した行。同じ値を書き戻して再描画を誘発しないため。
        private var reportedLine = 0

        /// UTF-16 の位置から行番号を引く。`lineIndex` は private なのでここを通す。
        func lineNumber(atUTF16Offset offset: Int) -> Int {
            lineIndex.line(atUTF16Offset: offset)
        }
        /// テキストビューに載せてある本文。
        ///
        /// `NSTextView.string` / `UITextView.text` は呼ぶたびに文字列を作り直すため、
        /// スクロールのたびに比較すると長い文書で無駄が大きい。こちらと比べる。
        var appliedText: String
        /// スクロール位置を読むために保持する。所有はビュー階層側。
        weak var textView: PlatformTextView?
        /// 最後に処理したスクロール依頼。同じものを二度実行しないため。
        var appliedScrollRequest: EditorScrollRequest?
        /// 最後に処理した選択依頼。同上。
        var appliedSelectionRequest: EditorSelectionRequest?
        /// 最後に処理した焦点の依頼。同上。
        var appliedFocusRequest: EditorFocusRequest?
        /// 最後に処理した「同じ語を選んで」の依頼。同上。
        var appliedCommandRequest: EditorCommandRequest?
        /// いま塗ってある検索のヒット。ハイライトのたびに上へ重ねる。
        var searchHighlight: SearchHighlight?
        /// 直前の打鍵で書き換わった範囲。差分ハイライトの起点にする。
        ///
        /// テキストビューの delegate（`textDidChange`）は「どこが変わったか」を
        /// 教えてくれない。文字列の記憶域の側から受け取る。
        var pendingEdit: NSRange?

        // MARK: - ジャンプ先の点灯

        /// 目次から飛んだ直後に光らせている行の範囲。消えたら nil。
        var flashRange: NSRange?
        /// 点灯の残り具合。1 が点いた直後、0 で消えている。
        /// 実際の濃さは外観ごとに違うので、決めるのはテーマ側（`jumpFlash(progress:)`）。
        var flashProgress: CGFloat = 0
        /// 薄れさせている最中の処理。次のジャンプが来たら取り消す。
        private var flashTask: Task<Void, Never>?

        /// 濃いまま置く時間。
        static let flashHold = Duration.milliseconds(800)
        /// 薄れていく時間。
        static let flashFade = Duration.milliseconds(5200)
        /// 薄れていく途中の書き直しの回数。30 fps 相当。
        static let flashSteps = 156
        #if canImport(AppKit)
        /// 行番号を描いているテキストビュー。表示していないときは nil のまま。
        weak var gutterTextView: FocusReportingTextView?
        #endif

        init(text: Binding<String>, theme: MarkdownTheme, topVisibleLine: Binding<Int>?) {
            self.text = text
            self.topVisibleLine = topVisibleLine
            self.highlighter = MarkdownHighlighter(theme: theme)
            self.appliedFontSize = theme.fontSize
            #if canImport(AppKit)
            self.appliedAppearanceName = theme.appearance.platformAppearance.name
            #endif
            self.appliedText = text.wrappedValue
            self.lineIndex = LineIndex(text.wrappedValue)
        }

        /// 属性を貼り直す。
        ///
        /// - Parameter edited: 直前の編集で書き換わった範囲。
        ///   渡せばその周辺だけ貼り直す。`nil` なら全文
        ///   （初回、テーマ変更、外から本文が差し替わったとき）。
        func highlight(_ storage: NSTextStorage?, source: String, edited: NSRange? = nil) {
            guard let storage else { return }
            appliedText = source
            lineIndex = LineIndex(source)
            highlighter.apply(to: storage, text: source, edited: edited)
            // ハイライタは属性を貼り直す（既存を捨てる）ので、検索の塗りは必ずその後。
            applySearchHighlight(to: storage)
            // 点灯はさらにその上。打鍵で貼り直されても消えないよう、ここに含める。
            applyFlash(to: storage)
            #if canImport(AppKit)
            gutterTextView?.lineNumbers?.lineIndex = lineIndex
            #endif
        }

        /// 検索でヒットした範囲を塗る。
        ///
        /// 文字色は `searchMatchText`（外観に追従しない暗い色）に差し替える。
        /// コードブロックの中では構文の色が付いており、背景だけ変えると
        /// 読めない組み合わせが出る。見出しの色もここで落ちるが、読めることを優先する。
        private func applySearchHighlight(to storage: NSTextStorage) {
            guard let searchHighlight, !searchHighlight.matches.isEmpty else { return }
            let theme = highlighter.theme

            storage.beginEditing()
            defer { storage.endEditing() }

            for (index, range) in searchHighlight.matches.enumerated() {
                // 本文と数え直しのあいだにずれがあり得る（依頼が1周期ぶん古い）。
                // 範囲外は塗らずに飛ばす。
                guard range.location >= 0, range.location + range.length <= storage.length else { continue }
                storage.addAttributes([
                    .backgroundColor: index == searchHighlight.current
                        ? theme.searchCurrentMatch
                        : theme.searchMatch,
                    .foregroundColor: theme.searchMatchText,
                ], range: range)
            }
        }

        /// ジャンプ先の行を光らせて、ゆっくり消す。
        ///
        /// 「どこに降りたか」を示すためだけの表示なので、残さない。
        /// ただし急に消えると見落とすので、1 秒ほど置いてから 5 秒かけて薄れさせる。
        func flash(line: Int) {
            flashTask?.cancel()

            let range = lineIndex.utf16Range(ofLine: line)
            guard range.length > 0 else {
                flashRange = nil
                flashProgress = 0
                return
            }
            flashRange = range
            flashProgress = 1
            repaintFlash()

            flashTask = Task { [weak self] in
                try? await Task.sleep(for: Self.flashHold)
                guard !Task.isCancelled else { return }

                let interval = Self.flashFade / Self.flashSteps
                for step in 1...Self.flashSteps {
                    try? await Task.sleep(for: interval)
                    guard !Task.isCancelled, let self else { return }
                    self.flashProgress = 1 - CGFloat(step) / CGFloat(Self.flashSteps)
                    self.repaintFlash()
                }

                guard !Task.isCancelled, let self else { return }
                // 薄れきったら、下に隠していた属性（コードブロックの背景など）を戻す。
                self.flashRange = nil
                self.flashProgress = 0
                self.highlight(self.textView?.textStorage, source: self.appliedText)
            }
        }

        /// 点灯している範囲だけ塗り直す。
        ///
        /// 全文を貼り直さない。薄れさせるあいだ 30 fps で走るので、
        /// ここで 5 ms を払うと目に見えて重くなる。
        private func repaintFlash() {
            guard let storage = textView?.textStorage else { return }
            applyFlash(to: storage)
        }

        /// ジャンプ先の行を、半透明の色で塗る。
        private func applyFlash(to storage: NSMutableAttributedString) {
            guard let flashRange, flashProgress > 0.01,
                  flashRange.location >= 0,
                  flashRange.length > 0,
                  flashRange.location + flashRange.length <= storage.length
            else { return }

            storage.addAttribute(
                .backgroundColor,
                value: highlighter.theme.jumpFlash(progress: flashProgress),
                range: flashRange
            )
        }

        /// その行が画面の上端に来るようスクロールする。
        func scroll(to line: Int) {
            let offset = lineIndex.utf16Offset(ofLine: line)
            #if canImport(AppKit)
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let scrollView = textView.enclosingScrollView
            else { return }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: offset, length: 0), actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            // 見出しの行が上端に来るようにする。
            let target = max(0, rect.minY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: target))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            #elseif canImport(UIKit)
            guard let textView else { return }
            textView.scrollRangeToVisible(NSRange(location: offset, length: 0))
            #endif
        }

        /// その範囲を画面の中ほどへ持ってきて、先頭にカーソルを置く。
        ///
        /// 上端合わせ（`scroll(to:)`）にしないのは、検索では前後の文脈も見たいため。
        /// カーソルを置くのは、検索バーを閉じたあとそのまま編集を続けられるようにするため。
        ///
        /// **範囲を「選択」してはいけない。** 検索欄に入力の焦点があるあいだ、
        /// テキストビューは非アクティブなので、AppKit が選択範囲を灰色
        /// （`unemphasizedSelectedTextBackgroundColor`）で塗る。これは属性の
        /// 背景色より後に描かれるため、ヒットの色が灰色に隠れる。
        /// 長さ 0 のカーソルなら塗りが出ない。
        func reveal(_ range: NSRange) {
            guard let textView else { return }
            // `textStorage` は AppKit では省略可能、UIKit では必ずある。
            #if canImport(AppKit)
            let length = textView.textStorage?.length ?? 0
            #else
            let length = textView.textStorage.length
            #endif
            let location = min(max(range.location, 0), length)
            let clamped = NSRange(location: location, length: min(range.length, length - location))
            // 送り先の見当を付けるのは範囲全体。置くのは先頭のカーソルだけ。
            let caret = NSRange(location: location, length: 0)

            #if canImport(AppKit)
            textView.setSelectedRange(caret)
            guard let layoutManager = textView.layoutManager,
                  let container = textView.textContainer,
                  let scrollView = textView.enclosingScrollView
            else { return }

            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: clamped, actualCharacterRange: nil
            )
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)
            let visibleHeight = scrollView.contentView.bounds.height
            // テキストコンテナの座標系はビューの余白ぶんずれている。足してから中央に置く。
            let center = rect.midY + textView.textContainerInset.height - visibleHeight / 2
            let limit = max(0, textView.frame.height - visibleHeight)

            scrollView.contentView.scroll(to: NSPoint(x: 0, y: min(max(0, center), limit)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            #elseif canImport(UIKit)
            textView.selectedRange = caret
            textView.scrollRangeToVisible(clamped)
            #endif
        }

        /// 「同じ語を選んで」を実行する。
        func run(_ command: EditorCommandRequest.Command) {
            guard let textView else { return }
            let text = appliedText
            #if canImport(AppKit)
            let selected = textView.selectedRanges.map(\.rangeValue)
            #else
            let selected = [textView.selectedRange]
            #endif
            guard let primary = selected.first else { return }

            // まだ語を選んでいなければ、カーソルのある語から始める。
            guard primary.length > 0 else {
                guard let word = MultiSelection.wordRange(at: primary.location, in: text) else { return }
                select([word])
                return
            }

            let word = (text as NSString).substring(with: primary)
            switch command {
            case .selectAllOccurrences:
                let all = MultiSelection.allOccurrences(of: word, in: text)
                if !all.isEmpty { select(all) }

            case .selectNextOccurrence:
                guard let next = MultiSelection.nextOccurrence(of: word, after: selected, in: text)
                else { return }
                select(selected + [next])
            }
        }

        private func select(_ ranges: [NSRange]) {
            guard let textView, let last = ranges.last else { return }
            #if canImport(AppKit)
            textView.selectedRanges = ranges.map { NSValue(range: $0) }
            textView.scrollRangeToVisible(last)
            #else
            textView.selectedRange = last
            #endif
        }

        /// 入力の焦点を編集画面に戻す。
        func takeFocus() {
            guard let textView else { return }
            #if canImport(AppKit)
            textView.window?.makeFirstResponder(textView)
            #elseif canImport(UIKit)
            textView.becomeFirstResponder()
            #endif
        }

        /// 書き換わった範囲を覚える。
        ///
        /// `NSTextStorageDelegate` として受け取る。テキストビューの delegate は
        /// 「変わった」ことしか教えてくれず、**どこが**変わったかは記憶域の側にしかない。
        ///
        /// ここでは記録だけ。編集の処理中に属性を触ってはいけない。
        ///
        /// 型の名前が AppKit と UIKit で違うので、`Platform.swift` の別名で受ける。
        func rememberEdit(range: NSRange, actions: PlatformTextStorageEditActions) {
            // 属性だけの変更（自分で貼ったハイライトなど）は無視する。
            guard actions.contains(.editedCharacters) else { return }
            pendingEdit = range
        }

        /// 表示範囲の先頭にある文字位置から行番号を求め、変わっていれば報告する。
        func reportTopLine(utf16Offset: Int) {
            guard let topVisibleLine else { return }
            let line = lineIndex.line(atUTF16Offset: utf16Offset)
            guard line != reportedLine else { return }
            reportedLine = line
            topVisibleLine.wrappedValue = line
        }
    }
}

// MARK: - macOS

#if canImport(AppKit)

/// 入力の焦点が出入りしたことを知らせるテキストビュー。
///
/// AppKit には「ファーストレスポンダが変わった」を伝える通知が無い。
/// 行番号の強調を出し入れするために、ここで拾って伝える。
///
/// `window?.firstResponder` を見に行かないのは、`becomeFirstResponder()` の
/// 時点ではウインドウ側がまだ更新されておらず、古い答えが返るため。
final class FocusReportingTextView: NSTextView {

    private(set) var isFocused = false
    /// 焦点が変わったときに呼ぶ。行番号を描き直させる。
    var onFocusChange: (() -> Void)?

    /// 左余白に描く行番号。出さないときは `nil`。
    var lineNumbers: LineNumberGutter? {
        didSet { needsDisplay = true }
    }

    // MARK: - 同じ語をまとめて書き換える

    /// 打ち込み先。複数選ばれているあいだだけ入る。
    ///
    /// **`selectedRanges` に頼れない。** AppKit は長さ0の選択をいくつ渡しても
    /// 1つのカーソルにまとめてしまう（実測）。消したあとの行き先はどれも長さ0なので、
    /// 選択に預けたままだと消えてしまい、続けて打った文字が先頭にしか入らない。
    /// だから自分で覚える。
    private var targets: [NSRange]?

    /// 自分で行き先を置き直している最中。選択が変わっても `targets` を捨てない。
    private var isRetargeting = false

    /// 変換中に凍らせた行き先。
    ///
    /// **未確定の文字列を AppKit は1か所にしか置けない。** 変換中は先頭だけが動き、
    /// 確定した時点で同じ文字列が残りへ広がる。
    ///
    /// ## 変換中に本文を書き換えてはいけない
    ///
    /// 打っているそばから全部を動かそうと、変換中に残りの行き先へ写してみたが、
    /// **入力が壊れた**（実測）。AppKit は入力プログラムの知らないところで本文が
    /// 変わったと見て変換を捨てる。1文字ごとに変換がやり直しになり、
    /// 「な」を打とうとすると `n` が確定して `nな` になる。
    ///
    /// `didChangeText()` を呼ばない、置く場所を明示するなど、何を削っても直らなかった。
    /// 記憶域を触った時点で崩れる。**変換が終わるまで本文には手を出さない。**
    ///
    /// 打っている様子は `drawComposing` が上から**描いて**見せる。
    /// 書かずに描くので、後ろの文字を押しのけられない代わりに入力が壊れない。
    private struct Composition {
        /// 変換が始まる前の打ち込み先。前から順に並ぶ。
        let frozen: [NSRange]
        /// 未確定の文字列を置く場所。`frozen` の添字。
        let primary: Int
    }

    private var composition: Composition?

    /// いま打ち込む先。選択が生きていればそちら、消したあとなら覚えていた行き先。
    private var currentTargets: [NSRange]? {
        let ranges = selectedRanges.map(\.rangeValue)
        if ranges.count > 1 { return ranges }
        if let targets, targets.count > 1 { return targets }
        return nil
    }

    /// カーソルが動いたら複数選択は終わり。
    ///
    /// クリックでも矢印キーでもここを通る。`setSelectedRange` も最後はここに来る。
    override func setSelectedRanges(
        _ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool
    ) {
        if !isRetargeting, composition == nil, targets != nil {
            targets = nil
            needsDisplay = true
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        let replacement = (string as? NSAttributedString)?.string ?? (string as? String) ?? ""

        // 変換の確定。決まった文字列を残りの行き先へ広げる。
        if let state = composition {
            composition = nil
            super.insertText(string, replacementRange: replacementRange)
            spread(replacement, of: state)
            return
        }
        guard let ranges = currentTargets else {
            return super.insertText(string, replacementRange: replacementRange)
        }
        apply(replacement, to: ranges)
    }

    /// 変換が始まった。行き先を凍らせて、確定を待つ。
    ///
    /// **本文には手を出さない。** 触ると変換が壊れる（`Composition` に詳しく書いた）。
    override func setMarkedText(
        _ string: Any, selectedRange: NSRange, replacementRange: NSRange
    ) {
        // 場所を指定されている変換（再変換）は預からない。狙いが違う。
        if composition == nil, replacementRange.location == NSNotFound,
           let ranges = currentTargets {
            let frozen = ranges.sorted { $0.location < $1.location }
            let caret = self.selectedRange().location
            composition = Composition(
                frozen: frozen, primary: frozen.firstIndex { $0.location == caret } ?? 0
            )
        }
        super.setMarkedText(
            string, selectedRange: selectedRange, replacementRange: replacementRange
        )
        // 変換中の文字を全部消した。広げるものは無い。
        if markedRange().location == NSNotFound { composition = nil }

        // 写しは描いているだけなので、本文が変わったことにならない。自分で描き直させる。
        setNeedsDisplay(visibleRect)
    }

    override func unmarkText() {
        super.unmarkText()
        // 変換を切り上げられた（焦点が外れたときなど）。確定は `insertText` が先に片付ける。
        composition = nil
        setNeedsDisplay(visibleRect)
    }

    override func deleteBackward(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.deleteBackward(sender)
        }
        delete(ranges, forward: false)
    }

    override func deleteForward(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.deleteForward(sender)
        }
        delete(ranges, forward: true)
    }

    /// 打ち込み先すべてで消す。
    ///
    /// 選んであるところはその範囲ごと、カーソルだけのところは隣の1文字。
    /// 消すものがどこにも無ければ何もしない。**先頭だけ消してしまわないこと。**
    private func delete(_ ranges: [NSRange], forward: Bool) {
        let deletions = MultiSelection.deletions(for: ranges, forward: forward, in: string)
        guard !deletions.isEmpty else { return }
        apply("", to: deletions)
    }

    // MARK: - 改行する

    /// その行を打ち始める前のブロック状態を返す。Coordinator が繋ぐ。
    ///
    /// **コードブロックの中では継がない**ための判断に使う。
    /// 繋がっていなければ「中ではない」とみなす（継ぐ方に倒れる）。
    var blockStateBeforeLine: ((Int) -> MarkdownBlockState)?

    /// 行頭からの UTF-16 位置を行番号に直す。Coordinator が繋ぐ。
    var lineNumber: ((Int) -> Int)?

    /// Return。リストの行なら印を継ぎ、印だけの行なら抜ける。判断は
    /// `LineContinuationRule`（`MarkdownCore`）にあり、ここは本文を書き換えるだけ。
    override func insertNewline(_ sender: Any?) {
        // 変換中と複数選択のときは触らない。
        // **複数選択で行ごとに違う印を継ぐのは、狙いが定まらない。**
        // 選んだ場所ごとに前の行が違うので、何が起きるか打つ前に見えない。
        guard composition == nil, currentTargets == nil,
              let decision = lineContinuation()
        else { return super.insertNewline(sender) }

        switch decision {
        case .plain:
            super.insertNewline(sender)
        case .carry(let prefix):
            super.insertText("\n" + prefix, replacementRange: selectedRange())
        case .end(let clearing):
            // 印だけの行を消して、改行だけ入れる。空行になってリストから抜ける。
            let caret = selectedRange().location
            super.insertText("\n", replacementRange: NSRange(location: caret - clearing,
                                                             length: clearing))
        }
    }

    /// いまのカーソル位置から、改行したときの振る舞いを決める。
    ///
    /// 選択範囲があるときは `nil`（ふつうの改行に任せる）。
    /// 選んだ文字を消しながら印を継ぐのは、望まれる場面が思いつかない。
    private func lineContinuation() -> LineContinuation? {
        let selection = selectedRange()
        guard selection.length == 0 else { return nil }

        let text = string as NSString
        let lineRange = text.lineRange(for: selection)
        // `lineRange(for:)` は改行を含む。行の中身だけを見たいので落とす。
        var contentLength = lineRange.length
        while contentLength > 0,
              let last = Unicode.Scalar(text.character(at: lineRange.location + contentLength - 1)),
              CharacterSet.newlines.contains(last) {
            contentLength -= 1
        }
        let line = text.substring(with: NSRange(location: lineRange.location, length: contentLength))

        let insideCode: Bool
        if let lineNumber, let blockStateBeforeLine,
           case .fencedCode = blockStateBeforeLine(lineNumber(lineRange.location)) {
            insideCode = true
        } else {
            insideCode = false
        }

        return LineContinuationRule.decide(
            line: line,
            caretUTF16Offset: selection.location - lineRange.location,
            isInsideCode: insideCode
        )
    }

    // MARK: - 深さを変える

    /// リストを深くするときに入れる1段ぶん。設定から降りてくる。
    var indentUnit: String = IndentStyle.fourSpaces.unit

    /// Tab。リストの行なら1段深くする。**それ以外はふつうにタブが入る。**
    override func insertTab(_ sender: Any?) {
        guard changeIndent(deepen: true) else { return super.insertTab(sender) }
    }

    /// ⇧Tab。リストの行なら1段浅くする。
    ///
    /// **浅くするときは設定を見ない。** 書かれているものを見て外す。
    /// スペースの文書をタブ設定で開いても、意図どおりに戻せるようにするため。
    override func insertBacktab(_ sender: Any?) {
        guard changeIndent(deepen: false) else { return super.insertBacktab(sender) }
    }

    /// - Returns: 深さを変えたら `true`。リストの行でなければ `false`（既定の動きに任せる）。
    private func changeIndent(deepen: Bool) -> Bool {
        // 変換中と複数選択のときは触らない。行ごとに前提が違う。
        guard composition == nil, currentTargets == nil else { return false }

        let text = string as NSString
        let selection = selectedRange()
        let lineRange = text.lineRange(for: selection)
        var contentLength = lineRange.length
        while contentLength > 0,
              let last = Unicode.Scalar(text.character(at: lineRange.location + contentLength - 1)),
              CharacterSet.newlines.contains(last) {
            contentLength -= 1
        }
        let line = text.substring(with: NSRange(location: lineRange.location, length: contentLength))

        if deepen {
            guard let unit = IndentChange.deepen(line: line, unit: indentUnit) else { return false }
            super.insertText(unit, replacementRange: NSRange(location: lineRange.location, length: 0))
        } else {
            guard let count = IndentChange.shallow(line: line) else { return false }
            super.insertText("", replacementRange: NSRange(location: lineRange.location, length: count))
        }
        return true
    }

    // MARK: - 貼り付ける

    /// ⌘V。**既定の実装は選んだところを全部消して、先頭にだけ入れる**（実測）。
    ///
    /// 残りは消えたまま何も入らないので、黙って中身が減る。
    /// しかも `insertText(_:replacementRange:)` を通らないため、打ち込みの側で
    /// 塞いだ道はここには効かない。自分で全箇所へ当てる。
    override func paste(_ sender: Any?) {
        guard composition == nil, pasteEverywhere(from: .general) else {
            return super.paste(sender)
        }
    }

    /// ⌥⇧⌘V。書式を捨てる点だけが違い、複数選択の扱いは ⌘V と同じ。
    override func pasteAsPlainText(_ sender: Any?) {
        guard composition == nil, pasteEverywhere(from: .general) else {
            return super.pasteAsPlainText(sender)
        }
    }

    /// クリップボードの中身を、打ち込み先すべてに入れる。
    ///
    /// **中身は分けない。** 複数行でも、そのまま各所へ同じだけ入れる。
    /// 貼り付けは元から「入れたものがそのまま入る」道具で、行が増えるのは
    /// カーソル1つのときにも起きる。複数選択だけ別の決まりにすると読めなくなる。
    ///
    /// 引数で受けるのは、確認のときに本物のクリップボードを汚さないため。
    ///
    /// - Returns: 当てたなら `true`。複数選択でない、または文字が取れなければ `false`
    ///   （呼ぶ側が `super` に戻す）。
    func pasteEverywhere(from pasteboard: NSPasteboard) -> Bool {
        guard let ranges = currentTargets, let replacement = plainText(from: pasteboard)
        else { return false }
        apply(replacement, to: ranges)
        return true
    }

    /// クリップボードから文字だけを取り出す。
    ///
    /// 書式付きしか入っていないことがある（ブラウザからの複写など）。
    /// 本文は素の文字列なので、どちらにしても文字だけを見る。
    private func plainText(from pasteboard: NSPasteboard) -> String? {
        if let text = pasteboard.string(forType: .string) { return text }
        let rich = pasteboard.readObjects(forClasses: [NSAttributedString.self], options: nil)
        return (rich?.first as? NSAttributedString)?.string
    }

    /// 選んである範囲すべてを置き換える。
    ///
    /// 1回の取り消し（⌘Z）で元に戻るよう、まとめて1つの編集として当てる。
    private func apply(_ replacement: String, to ranges: [NSRange]) {
        guard let storage = textStorage else { return }
        let sorted = ranges.sorted { $0.location < $1.location }
        guard shouldChangeText(
            inRanges: sorted.map { NSValue(range: $0) },
            replacementStrings: sorted.map { _ in replacement }
        ) else { return }

        storage.beginEditing()
        // 後ろから当てる。前から当てると2つ目以降の位置がずれる。
        for range in sorted.reversed() {
            guard range.location >= 0, range.location + range.length <= storage.length else { continue }
            storage.replaceCharacters(in: range, with: replacement)
        }
        storage.endEditing()
        didChangeText()

        retarget(to: MultiSelection.carets(after: sorted, replacedWith: replacement))
    }

    /// 確定した文字列を、先頭以外の行き先にも当てる。
    ///
    /// 変換中は本文を触っていないので、凍らせた位置がそのまま使える。
    private func spread(_ replacement: String, of state: Composition) {
        // 先頭が確定したぶんだけ、後ろにある行き先がずれている。
        let primary = state.frozen[state.primary]
        let delta = (replacement as NSString).length - primary.length
        let end = primary.location + primary.length
        var others: [NSRange] = []
        for (index, range) in state.frozen.enumerated() where index != state.primary {
            others.append(
                range.location >= end
                    ? NSRange(location: range.location + delta, length: range.length) : range
            )
        }

        if !others.isEmpty { apply(replacement, to: others) }
        // 行き先は全部から数え直す。先頭を外したままだと1つ抜ける。
        retarget(to: MultiSelection.carets(after: state.frozen, replacedWith: replacement))
    }

    // MARK: - 選び直す

    /// → で、すべてのカーソルを同じだけ動かす。**複数選択は続く。**
    ///
    /// 消したあとの位置から、隣の語へ狙いを移すために要る。
    /// 「改行だけ選んだ状態から ← を2回、⇧→ で全部の `。` を選ぶ」といった動き方。
    override func moveRight(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveRight(sender)
        }
        move(ranges, forward: true)
    }

    override func moveLeft(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveLeft(sender)
        }
        move(ranges, forward: false)
    }

    override func moveForward(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveForward(sender)
        }
        move(ranges, forward: true)
    }

    override func moveBackward(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveBackward(sender)
        }
        move(ranges, forward: false)
    }

    private func move(_ ranges: [NSRange], forward: Bool) {
        retarget(to: MultiSelection.moving(ranges, forward: forward, in: string))
    }

    /// ⇧→ で、すべての行き先の選択を1文字ぶん伸ばす。
    ///
    /// 打ち間違えたときに選び直せる道が要る。`⌘D` で選び直そうにも、
    /// 消したあとはカーソルしか無く、選ぶ語が残っていない。
    override func moveRightAndModifySelection(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveRightAndModifySelection(sender)
        }
        extend(ranges, forward: true)
    }

    /// ⇧← で、伸ばした選択を1文字ぶん縮める。**始点は動かさない。**
    override func moveLeftAndModifySelection(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveLeftAndModifySelection(sender)
        }
        extend(ranges, forward: false)
    }

    override func moveForwardAndModifySelection(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveForwardAndModifySelection(sender)
        }
        extend(ranges, forward: true)
    }

    override func moveBackwardAndModifySelection(_ sender: Any?) {
        guard composition == nil, let ranges = currentTargets else {
            return super.moveBackwardAndModifySelection(sender)
        }
        extend(ranges, forward: false)
    }

    private func extend(_ ranges: [NSRange], forward: Bool) {
        let extended = MultiSelection.extending(ranges, forward: forward, in: string)
        guard extended != ranges else { return }
        retarget(to: extended)
    }

    /// 次に打ち込む先を置き直す。
    private func retarget(to carets: [NSRange]) {
        targets = carets.count > 1 ? carets : nil
        isRetargeting = true
        selectedRanges = carets.map { NSValue(range: $0) }
        isRetargeting = false
        needsDisplay = true
    }

    /// 本文より先に呼ばれる。ここで左余白へ行番号を描く。
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lineNumbers else { return }
        let active = isFocused ? lineNumbers.lineIndex.line(atUTF16Offset: selectedRange().location) : nil
        lineNumbers.draw(in: rect, of: self, activeLine: active)
    }

    /// 本文の上に、余分なカーソルと変換中の写しを描く。
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let composition {
            drawComposing(composition, in: dirtyRect)
        } else {
            drawExtraCarets(in: dirtyRect)
        }
    }

    /// 余分なカーソルを描く。
    ///
    /// AppKit は長さ0の選択を1つにまとめてしまうので、消したあとの行き先は
    /// 1本しか見えない。どこに打ち込まれるのか分からないままになるので自分で描く。
    /// **点滅はしない。** 本物と拍を合わせるには消えた瞬間に描き直す必要があり、
    /// 見せたいのは「ここにも入る」だけなので、出しっぱなしで足りる。
    private func drawExtraCarets(in dirtyRect: NSRect) {
        guard let targets, targets.count > 1 else { return }

        insertionPointColor.setFill()
        let primary = selectedRange().location
        for target in targets where target.location != primary {
            guard let rect = caretRect(at: target.location) else { continue }
            guard rect.intersects(dirtyRect) else { continue }
            rect.fill()
        }
    }

    /// 変換中の文字列を、先頭以外の行き先にも描く。
    ///
    /// **本文には書かない。** 変換中に記憶域を触ると入力が壊れる
    /// （`Composition` に書いた）。書けないので、上から描く。
    ///
    /// 描くだけなので後ろの文字を押しのけられない。**下に敷いてある文字は隠す。**
    /// 確定すれば本文に入り、そこで初めて行が組み直される。
    private func drawComposing(_ state: Composition, in dirtyRect: NSRect) {
        let marked = markedRange()
        guard marked.location != NSNotFound, marked.length > 0, let layoutManager,
              let container = textContainer
        else { return }

        let text = (string as NSString).substring(with: marked)

        // 先頭に未確定のぶんが入ったので、その後ろにある行き先はずれている。
        let primary = state.frozen[state.primary]
        let delta = marked.length - primary.length
        let end = primary.location + primary.length

        for (index, range) in state.frozen.enumerated() where index != state.primary {
            let location = range.location >= end ? range.location + delta : range.location
            guard let caret = caretRect(at: location) else { continue }
            let composing = composingText(text, goingTo: location)
            let width = composing.size().width

            // 元からあった語も隠す。半分だけ残ると別の語に読めてしまう。
            let covered = layoutManager.boundingRect(
                forGlyphRange: layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: location, length: range.length),
                    actualCharacterRange: nil
                ),
                in: container
            )
            let box = NSRect(
                x: caret.minX, y: caret.minY,
                width: max(width, covered.width), height: caret.height
            )
            guard box.intersects(dirtyRect) else { continue }

            backgroundColor.setFill()
            box.fill()
            composing.draw(at: box.origin)
        }
    }

    /// 変換中の文字列を、打ち込む先の見た目で組む。
    ///
    /// **書体は打ち込む先から借りる。** 確定すればその場所の属性を継ぐので、
    /// 借りておけば確定の前後で見た目が飛ばない。見出しの中なら見出しの大きさになる。
    private func composingText(_ text: String, goingTo location: Int) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: textColor ?? NSColor.textColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        if let storage = textStorage, storage.length > 0 {
            let index = min(max(location, 0), storage.length - 1)
            if let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont {
                attributes[.font] = font
            }
        }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// その文字位置に立つカーソルの矩形。
    private func caretRect(at location: Int) -> NSRect? {
        guard let layoutManager, let storage = textStorage,
              location >= 0, location <= storage.length
        else { return nil }

        let line: NSRect
        let offset: CGFloat
        if location < storage.length {
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            line = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            offset = layoutManager.location(forGlyphAt: glyph).x
        } else {
            // 本文の末尾。最後の行の外にあるので、専用の矩形を使う。
            line = layoutManager.extraLineFragmentRect
            offset = 0
            guard line.height > 0 else { return nil }
        }

        return NSRect(
            x: line.minX + offset + textContainerInset.width,
            y: line.minY + textContainerInset.height,
            width: 1, height: line.height
        )
    }

    /// 見えているところだけ描き直す。カーソルが動くたびに全体を捨てない。
    func redrawLineNumbers() {
        guard lineNumbers != nil else { return }
        setNeedsDisplay(visibleRect)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted, !isFocused {
            isFocused = true
            onFocusChange?()
        }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            // 焦点が離れたら複数選択は終わり。戻ってきたときに古い行き先へ打ち込ませない。
            targets = nil
            composition = nil
        }
        if resigned, isFocused {
            isFocused = false
            onFocusChange?()
        }
        return resigned
    }
}

extension MarkdownEditorView: NSViewRepresentable {

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let base = scrollView.documentView as? NSTextView,
              let container = base.textContainer
        else { return scrollView }

        // 焦点の出入りを知るためにテキストビューだけ差し替える。
        // `scrollableTextView()` が組み立てた TextKit 一式（テキストストレージ、
        // レイアウトマネージャ、テキストコンテナ）はそのまま引き継ぐので、
        // 折り返しやスクロールの設定はここで作り直さなくてよい。
        let textView = FocusReportingTextView(frame: base.frame, textContainer: container)
        textView.autoresizingMask = base.autoresizingMask
        textView.minSize = base.minSize
        textView.maxSize = base.maxSize
        textView.isVerticallyResizable = base.isVerticallyResizable
        textView.isHorizontallyResizable = base.isHorizontallyResizable
        scrollView.documentView = textView
        textView.onFocusChange = { [weak coordinator = context.coordinator] in
            coordinator?.gutterTextView?.redrawLineNumbers()
        }

        textView.delegate = context.coordinator
        // 「どこが書き換わったか」を受け取る。差分ハイライトの起点になる。
        textView.textStorage?.delegate = context.coordinator
        textView.indentUnit = indentStyle.unit
        // 改行でリストを継ぐかの判断に使う。コードブロックの中では継がない。
        textView.lineNumber = { [weak coordinator = context.coordinator] offset in
            coordinator?.lineNumber(atUTF16Offset: offset) ?? 0
        }
        textView.blockStateBeforeLine = { [weak coordinator = context.coordinator] line in
            coordinator?.highlighter.blockState(beforeLine: line) ?? .blank
        }
        textView.allowsUndo = true
        // 書式付きテキストを持ち込ませない。装飾はハイライタだけが付ける。
        textView.isRichText = false
        // Markdown では引用符やハイフンの自動変換が邪魔になる。
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: LineNumberGutter.textPadding, height: 16)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true

        // 順序が重要。`apply` は `textView.textColor` を設定するが、これは
        // 本文全体の色を塗り替える。ハイライトより後に呼ぶと装飾が消える。
        // 必ず「テーマ → 本文 → ハイライト」の順で行う。
        textView.string = text
        apply(theme, to: scrollView)
        context.coordinator.searchHighlight = searchHighlight
        context.coordinator.highlight(textView.textStorage, source: text)

        // スクロールに追従してプレビューを動かすため、表示範囲の変化を拾う。
        // target/selector 形式の監視は、監視者が解放された時点で自動的に外れるため
        // 明示的な解除が要らない（macOS 10.11 以降）。
        context.coordinator.textView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.editorDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )

        updateGutter(on: scrollView, textView: textView, coordinator: context.coordinator)
        return scrollView
    }

    /// 行番号を、設定に合わせて付け外しする。
    ///
    /// 本文の場所は `textContainerInset` で空ける。左右に等しく効くので
    /// 右の余白も同じだけ広がるが、テキストコンテナの幅の決め方には触らないため
    /// 折り返しの追従が壊れない。
    private func updateGutter(on scrollView: NSScrollView, textView: NSTextView, coordinator: Coordinator) {
        guard let textView = textView as? FocusReportingTextView else { return }

        guard showsLineNumbers else {
            textView.lineNumbers = nil
            coordinator.gutterTextView = nil
            textView.textContainerInset.width = LineNumberGutter.textPadding
            return
        }

        var gutter = textView.lineNumbers ?? LineNumberGutter(theme: theme, lineIndex: LineIndex(text))
        gutter.theme = theme
        textView.lineNumbers = gutter
        coordinator.gutterTextView = textView

        let wanted = gutter.textContainerInsetWidth
        if abs(textView.textContainerInset.width - wanted) > 0.5 {
            textView.textContainerInset.width = wanted
        }
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.topVisibleLine = topVisibleLine
        coordinator.highlighter.theme = theme
        // 設定で変えたら、開いている窓にもすぐ効かせる。
        (textView as? FocusReportingTextView)?.indentUnit = indentStyle.unit

        let resolved = theme.appearance.platformAppearance
        let themeChanged = coordinator.appliedFontSize != theme.fontSize
            || coordinator.appliedAppearanceName != resolved.name
        let textChanged = coordinator.appliedText != text
        let searchChanged = coordinator.searchHighlight != searchHighlight

        if textChanged {
            // 外から本文が差し替わったとき（ファイルを開いた、取り消した）。
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }
        if themeChanged {
            coordinator.appliedFontSize = theme.fontSize
            coordinator.appliedAppearanceName = resolved.name
            apply(theme, to: scrollView)
            scrollView.backgroundColor = theme.background
        }
        if searchChanged {
            coordinator.searchHighlight = searchHighlight
        }
        if textChanged || themeChanged || searchChanged {
            // 検索の塗りだけを剥がす手は無い（コードブロックの背景と区別が付かない）。
            // 全文を貼り直す。5万文字で 5.3 ms なので、送るたびに走らせても間に合う。
            coordinator.highlight(textView.textStorage, source: text)
        }
        if let request = scrollRequest, request != coordinator.appliedScrollRequest {
            coordinator.appliedScrollRequest = request
            coordinator.scroll(to: request.line)
            // 目次から飛んだことが分かるよう、その行を光らせる。
            coordinator.flash(line: request.line)
        }
        if let request = selectionRequest, request != coordinator.appliedSelectionRequest {
            coordinator.appliedSelectionRequest = request
            coordinator.reveal(request.range)
        }
        if let request = focusRequest, request != coordinator.appliedFocusRequest {
            coordinator.appliedFocusRequest = request
            coordinator.takeFocus()
        }
        if let request = commandRequest, request != coordinator.appliedCommandRequest {
            coordinator.appliedCommandRequest = request
            coordinator.run(request.command)
        }
        updateGutter(on: scrollView, textView: textView, coordinator: coordinator)
    }

    /// 外観はスクロールビューに設定する。中のテキストビューは親から受け継ぐ。
    ///
    /// 色は動的な色のまま貼ってある。ここで外観を上書きすると、
    /// 描画時にそちらで解決し直されるので、属性を貼り直す必要はない。
    private func apply(_ theme: MarkdownTheme, to scrollView: NSScrollView) {
        scrollView.appearance = theme.appearance.platformAppearance
        scrollView.backgroundColor = theme.background

        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.backgroundColor = theme.background
        textView.insertionPointColor = theme.text
        textView.font = theme.bodyFont
        textView.textColor = theme.text
    }
}

extension NSTextView {
    /// 表示範囲の左上にある文字の位置（UTF-16 オフセット）。
    ///
    /// `characterIndexForInsertion(at:)` を使うのは、TextKit 1 と TextKit 2 の
    /// どちらで動いていても同じように答えが返るため。レイアウトマネージャに
    /// 直接触ると、どちらで動いているかを気にすることになる。
    var topVisibleCharacterIndex: Int {
        let origin = CGPoint(
            x: textContainerInset.width,
            y: visibleRect.minY + textContainerInset.height
        )
        return characterIndexForInsertion(at: origin)
    }
}

/// `NSTextStorageDelegate` は主スレッド専用と宣言されていない
/// （文字列の記憶域自体は他スレッドでも使えるため）。
/// ここで見ているのは画面に載っているテキストビューの記憶域だけなので、
/// 呼ばれるのは必ず主スレッド。`@preconcurrency` で受ける。
extension MarkdownEditorView.Coordinator: @preconcurrency NSTextStorageDelegate {

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        rememberEdit(range: editedRange, actions: editedMask)
    }
}

extension MarkdownEditorView.Coordinator: NSTextViewDelegate {

    public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        var source = textView.string
        // **必ず Swift 側の記憶域へ写すこと。**
        // `NSTextView.string` は NSString 由来の文字列を返す。1文字ずつ走査すると
        // 橋渡しの費用が毎回かかり、トークン化が 2.6 ms → 9.0 ms、
        // 行の索引作りが 0.3 ms → 2.5 ms まで落ちる（1.8万文字で実測）。
        // 写すのは 0.6 ms。打鍵のたびに払っても釣りが来る。
        source.makeContiguousUTF8()
        text.wrappedValue = source
        let edited = pendingEdit
        pendingEdit = nil
        highlight(textView.textStorage, source: source, edited: edited)
        gutterTextView?.redrawLineNumbers()
    }

    @objc func editorDidScroll(_ notification: Notification) {
        guard let textView else { return }
        reportTopLine(utf16Offset: textView.topVisibleCharacterIndex)
        gutterTextView?.redrawLineNumbers()
    }

    /// カーソルが動いたら、強調する行番号を描き直す。
    public func textViewDidChangeSelection(_ notification: Notification) {
        gutterTextView?.redrawLineNumbers()
    }
}

#endif

// MARK: - iOS

#if !canImport(AppKit) && canImport(UIKit)

extension MarkdownEditorView: UIViewRepresentable {

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.textStorage.delegate = context.coordinator
        textView.alwaysBounceVertical = true
        // Markdown では自動修正・自動変換が邪魔になる。
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)

        textView.text = text
        apply(theme, to: textView)
        context.coordinator.textView = textView
        context.coordinator.searchHighlight = searchHighlight
        context.coordinator.highlight(textView.textStorage, source: text)
        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.topVisibleLine = topVisibleLine
        coordinator.highlighter.theme = theme

        let themeChanged = coordinator.appliedFontSize != theme.fontSize
        let textChanged = coordinator.appliedText != text
        let searchChanged = coordinator.searchHighlight != searchHighlight

        if textChanged {
            let selection = textView.selectedRange
            textView.text = text
            textView.selectedRange = selection
        }
        if themeChanged {
            coordinator.appliedFontSize = theme.fontSize
            apply(theme, to: textView)
        }
        if searchChanged {
            coordinator.searchHighlight = searchHighlight
        }
        if textChanged || themeChanged || searchChanged {
            coordinator.highlight(textView.textStorage, source: text)
        }
        if let request = scrollRequest, request != coordinator.appliedScrollRequest {
            coordinator.appliedScrollRequest = request
            coordinator.scroll(to: request.line)
            // 目次から飛んだことが分かるよう、その行を光らせる。
            coordinator.flash(line: request.line)
        }
        if let request = selectionRequest, request != coordinator.appliedSelectionRequest {
            coordinator.appliedSelectionRequest = request
            coordinator.reveal(request.range)
        }
        if let request = focusRequest, request != coordinator.appliedFocusRequest {
            coordinator.appliedFocusRequest = request
            coordinator.takeFocus()
        }
        if let request = commandRequest, request != coordinator.appliedCommandRequest {
            coordinator.appliedCommandRequest = request
            coordinator.run(request.command)
        }
    }

    private func apply(_ theme: MarkdownTheme, to textView: UITextView) {
        // 色は動的な色のまま貼ってある。外観を上書きすると描画時に解決し直される。
        textView.overrideUserInterfaceStyle = theme.appearance.platformInterfaceStyle
        textView.backgroundColor = theme.background
        textView.tintColor = theme.text
        textView.font = theme.bodyFont
        textView.textColor = theme.text
    }
}

/// `NSTextStorageDelegate` は主スレッド専用と宣言されていない
/// （文字列の記憶域自体は他スレッドでも使えるため）。
/// ここで見ているのは画面に載っているテキストビューの記憶域だけなので、
/// 呼ばれるのは必ず主スレッド。`@preconcurrency` で受ける。
extension MarkdownEditorView.Coordinator: @preconcurrency NSTextStorageDelegate {

    public func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorage.EditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        rememberEdit(range: editedRange, actions: editedMask)
    }
}

extension MarkdownEditorView.Coordinator: UITextViewDelegate {

    public func textViewDidChange(_ textView: UITextView) {
        // NSString 由来のままだと走査が遅い。Swift 側の記憶域へ写す（macOS 側の注記を参照）。
        var source = textView.text ?? ""
        source.makeContiguousUTF8()
        text.wrappedValue = source
        let edited = pendingEdit
        pendingEdit = nil
        highlight(textView.textStorage, source: source, edited: edited)
    }

    /// `UITextView` は `UIScrollView` なので、スクロールもこの delegate に届く。
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let textView = scrollView as? UITextView else { return }
        reportTopLine(utf16Offset: textView.topVisibleCharacterIndex)
    }
}

extension UITextView {
    /// 表示範囲の左上にある文字の位置（UTF-16 オフセット）。
    var topVisibleCharacterIndex: Int {
        let origin = CGPoint(
            x: textContainerInset.left,
            y: contentOffset.y + textContainerInset.top
        )
        guard let position = closestPosition(to: origin) else { return 0 }
        return offset(from: beginningOfDocument, to: position)
    }
}

#endif
