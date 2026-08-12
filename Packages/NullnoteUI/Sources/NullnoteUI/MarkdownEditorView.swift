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
    /// 左端に行番号を出すか。
    var showsLineNumbers: Bool
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
        showsLineNumbers: Bool = false
    ) {
        self._text = text
        self.theme = theme
        self.topVisibleLine = topVisibleLine
        self.scrollRequest = scrollRequest
        self.selectionRequest = selectionRequest
        self.searchHighlight = searchHighlight
        self.showsLineNumbers = showsLineNumbers
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

    /// 本文より先に呼ばれる。ここで左余白へ行番号を描く。
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let lineNumbers else { return }
        let active = isFocused ? lineNumbers.lineIndex.line(atUTF16Offset: selectedRange().location) : nil
        lineNumbers.draw(in: rect, of: self, activeLine: active)
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
