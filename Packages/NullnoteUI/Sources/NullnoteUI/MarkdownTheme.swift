import CoreGraphics
import Foundation

/// どの外観で描くか。
///
/// 色そのものは1組しか持たない。動的な色がライトとダークの両方の値を持っていて、
/// これがどちらで解決するかを決める。配色を2組持つより、破綻する余地が少ない。
public enum MarkdownAppearance: String, CaseIterable, Identifiable, Sendable {
    /// システムの設定に従う。
    case system
    case light
    case dark

    public var id: String { rawValue }

    /// 画面に出す名前。設定画面とフッターで同じ言葉を使う。
    public var label: String {
        switch self {
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }
}

/// エディタとプレビューの配色・字送り。
///
/// 色は外観に追従する動的な色として持つ。属性文字列に入れたまま
/// ライト／ダークが切り替わっても、描画時に解決し直されるので貼り直す必要はない。
public struct MarkdownTheme {

    /// 本文の文字サイズ。
    public var fontSize: CGFloat
    /// ライト／ダークのどちらで描くか。
    public var appearance: MarkdownAppearance

    public var background: PlatformColor
    /// 本文。
    public var text: PlatformColor
    /// 記法そのもの（`#` `*` `|` など）。本文より薄くして目立たせない。
    public var marker: PlatformColor
    public var heading: PlatformColor
    /// インラインコード（`` `code` ``）の文字色。
    public var code: PlatformColor
    public var codeBackground: PlatformColor
    /// コードブロックの中の簡易ハイライト。
    /// これ以外（識別子など）は `text` で描く。
    public var codeKeyword: PlatformColor
    public var codeString: PlatformColor
    public var codeComment: PlatformColor
    public var codeNumber: PlatformColor
    public var link: PlatformColor
    public var quote: PlatformColor
    /// チェックボックスや表の見出しなど、注意を引かせたい要素。
    public var accent: PlatformColor

    public init(
        fontSize: CGFloat,
        appearance: MarkdownAppearance = .system,
        background: PlatformColor,
        text: PlatformColor,
        marker: PlatformColor,
        heading: PlatformColor,
        code: PlatformColor,
        codeBackground: PlatformColor,
        codeKeyword: PlatformColor,
        codeString: PlatformColor,
        codeComment: PlatformColor,
        codeNumber: PlatformColor,
        link: PlatformColor,
        quote: PlatformColor,
        accent: PlatformColor
    ) {
        self.fontSize = fontSize
        self.appearance = appearance
        self.background = background
        self.text = text
        self.marker = marker
        self.heading = heading
        self.code = code
        self.codeBackground = codeBackground
        self.codeKeyword = codeKeyword
        self.codeString = codeString
        self.codeComment = codeComment
        self.codeNumber = codeNumber
        self.link = link
        self.quote = quote
        self.accent = accent
    }

    /// 表の見出し行の背景。本文の背景から一段ずらして、見出しだと分かるようにする。
    ///
    /// いまはコードブロックの背景と同じ値。役割が違うので名前は分けてある
    /// （どちらかだけ変えたくなったときに困らない）。
    public var tableHeaderBackground: PlatformColor { codeBackground }

    /// 表の罫線。
    public var tableBorder: PlatformColor { marker.withAlphaComponent(0.45) }

    /// 今カーソルがある行の番号に使う色。
    ///
    /// 配色表に持たず、OS のハイライト／アクセント設定に従う。
    /// ここだけ利用者の設定色が出るのは意図的で、
    /// 「今どこにいるか」は OS の選択表示と揃えた方が迷わない。
    ///
    /// **`selectedTextBackgroundColor`（ハイライト色そのもの）は使えない。**
    /// あれは選択範囲の「背景」用に明度を上げた色で、文字色に使うと
    /// ライトの背景（#F5F5F5）とのコントラスト比が 1.4 程度しか出ず読めない。
    /// 同じ設定から導かれる `selectedContentBackgroundColor` は
    /// 選択項目の背景色で、文字として置いても読める濃さがある。
    public var activeLineNumber: PlatformColor {
        #if canImport(AppKit)
        .selectedContentBackgroundColor
        #else
        .tintColor
        #endif
    }

    public static func standard(
        fontSize: CGFloat = MarkdownTheme.defaultFontSize,
        appearance: MarkdownAppearance = .system
    ) -> MarkdownTheme {
        MarkdownTheme(
            fontSize: fontSize,
            appearance: appearance,
            background: .dynamic(light: .rgb(245, 245, 245), dark: .rgb(41, 50, 56)),
            text: .dynamic(light: .rgb(28, 28, 30), dark: .rgb(226, 226, 230)),
            marker: .dynamic(light: .rgb(168, 170, 178), dark: .rgb(118, 120, 130)),
            heading: .dynamic(light: .rgb(10, 10, 12), dark: .rgb(245, 245, 248)),
            code: .dynamic(light: .rgb(180, 60, 90), dark: .rgb(240, 150, 175)),
            codeBackground: .dynamic(light: .rgb(234, 234, 238), dark: .rgb(50, 60, 67)),
            codeKeyword: .dynamic(light: .rgb(122, 62, 157), dark: .rgb(206, 147, 240)),
            codeString: .dynamic(light: .rgb(154, 74, 46), dark: .rgb(240, 174, 121)),
            codeComment: .dynamic(light: .rgb(63, 107, 46), dark: .rgb(140, 192, 111)),
            codeNumber: .dynamic(light: .rgb(23, 107, 117), dark: .rgb(143, 220, 230)),
            link: .dynamic(light: .rgb(20, 105, 200), dark: .rgb(105, 170, 250)),
            quote: .dynamic(light: .rgb(105, 110, 122), dark: .rgb(150, 155, 168)),
            accent: .dynamic(light: .rgb(0, 128, 255), dark: .rgb(0, 128, 255))
        )
    }

    public static let defaultFontSize: CGFloat = 14
    public static let minimumFontSize: CGFloat = 10
    public static let maximumFontSize: CGFloat = 28

    // MARK: - 派生する値

    /// 見出しの拡大率。レベルが浅いほど大きい。
    public func headingFontSize(level: Int) -> CGFloat {
        let scale: CGFloat
        switch level {
        case 1: scale = 1.60
        case 2: scale = 1.40
        case 3: scale = 1.25
        case 4: scale = 1.15
        case 5: scale = 1.08
        default: scale = 1.00
        }
        return (fontSize * scale).rounded()
    }

    public var bodyFont: PlatformFont { .editorBody(size: fontSize) }
    public var monospacedFont: PlatformFont { .editorMonospaced(size: fontSize) }
}
