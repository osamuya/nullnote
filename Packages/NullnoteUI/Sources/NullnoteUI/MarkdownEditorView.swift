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
@MainActor
public struct MarkdownEditorView {

    @Binding var text: String
    var theme: MarkdownTheme
    /// 画面の一番上に見えている行。1 始まり。プレビューとの同期に使う。
    var topVisibleLine: Binding<Int>?

    public init(
        text: Binding<String>,
        theme: MarkdownTheme,
        topVisibleLine: Binding<Int>? = nil
    ) {
        self._text = text
        self.theme = theme
        self.topVisibleLine = topVisibleLine
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
        var appliedAppearance: MarkdownAppearance
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

        init(text: Binding<String>, theme: MarkdownTheme, topVisibleLine: Binding<Int>?) {
            self.text = text
            self.topVisibleLine = topVisibleLine
            self.highlighter = MarkdownHighlighter(theme: theme)
            self.appliedFontSize = theme.fontSize
            self.appliedAppearance = theme.appearance
            self.appliedText = text.wrappedValue
            self.lineIndex = LineIndex(text.wrappedValue)
        }

        func highlight(_ storage: NSTextStorage?, source: String) {
            guard let storage else { return }
            appliedText = source
            lineIndex = LineIndex(source)
            highlighter.apply(to: storage, text: source)
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

extension MarkdownEditorView: NSViewRepresentable {

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.allowsUndo = true
        // 書式付きテキストを持ち込ませない。装飾はハイライタだけが付ける。
        textView.isRichText = false
        // Markdown では引用符やハイフンの自動変換が邪魔になる。
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 12, height: 16)

        textView.string = text
        context.coordinator.highlight(textView.textStorage, source: text)

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = true
        apply(theme, to: scrollView)

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

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.topVisibleLine = topVisibleLine
        coordinator.highlighter.theme = theme

        let themeChanged = coordinator.appliedFontSize != theme.fontSize
            || coordinator.appliedAppearance != theme.appearance
        let textChanged = coordinator.appliedText != text

        if textChanged {
            // 外から本文が差し替わったとき（ファイルを開いた、取り消した）。
            let selection = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selection
        }
        if themeChanged {
            coordinator.appliedFontSize = theme.fontSize
            coordinator.appliedAppearance = theme.appearance
            apply(theme, to: scrollView)
            scrollView.backgroundColor = theme.background
        }
        if textChanged || themeChanged {
            coordinator.highlight(textView.textStorage, source: text)
        }
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

extension MarkdownEditorView.Coordinator: NSTextViewDelegate {

    public func textDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        let source = textView.string
        text.wrappedValue = source
        highlight(textView.textStorage, source: source)
    }

    @objc func editorDidScroll(_ notification: Notification) {
        guard let textView else { return }
        reportTopLine(utf16Offset: textView.topVisibleCharacterIndex)
    }
}

#endif

// MARK: - iOS

#if !canImport(AppKit) && canImport(UIKit)

extension MarkdownEditorView: UIViewRepresentable {

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
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
        context.coordinator.highlight(textView.textStorage, source: text)
        return textView
    }

    public func updateUIView(_ textView: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.text = $text
        coordinator.topVisibleLine = topVisibleLine
        coordinator.highlighter.theme = theme

        let themeChanged = coordinator.appliedFontSize != theme.fontSize
            || coordinator.appliedAppearance != theme.appearance
        let textChanged = coordinator.appliedText != text

        if textChanged {
            let selection = textView.selectedRange
            textView.text = text
            textView.selectedRange = selection
        }
        if themeChanged {
            coordinator.appliedFontSize = theme.fontSize
            coordinator.appliedAppearance = theme.appearance
            apply(theme, to: textView)
        }
        if textChanged || themeChanged {
            coordinator.highlight(textView.textStorage, source: text)
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

extension MarkdownEditorView.Coordinator: UITextViewDelegate {

    public func textViewDidChange(_ textView: UITextView) {
        let source = textView.text ?? ""
        text.wrappedValue = source
        highlight(textView.textStorage, source: source)
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
