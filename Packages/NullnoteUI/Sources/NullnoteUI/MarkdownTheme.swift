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
    /// 検索でヒットした語の背景。
    public var searchMatch: PlatformColor
    /// 検索でいま見ているヒットの背景。ほかのヒットより一段強くする。
    public var searchCurrentMatch: PlatformColor
    /// ヒットの上に載せる文字の色。
    ///
    /// **外観に追従させない。** 追従させると、ダークでは白い文字を載せることになり、
    /// 背景の側を暗く濁らせるほかなくなる（黄色が茶色になる）。
    /// 明るい原色を両方の外観で使うために、文字の方を暗い色で固定する。
    public var searchMatchText: PlatformColor

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
        accent: PlatformColor,
        searchMatch: PlatformColor,
        searchCurrentMatch: PlatformColor,
        searchMatchText: PlatformColor
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
        self.searchMatch = searchMatch
        self.searchCurrentMatch = searchCurrentMatch
        self.searchMatchText = searchMatchText
    }

    /// 取り消した文字。
    ///
    /// 線を引くだけでなく、文字自体を本文より沈ませる。
    /// 「もう読まなくてよい」ことが、ぱっと見で分かるようにするため。
    public var struckText: PlatformColor { quote }

    /// 目次で今いる項目の背景。
    ///
    /// OS のアクセント色は使わない。窓が前面かどうかで色が変わってしまい、
    /// 「今どこを見ているか」を示すだけの用途には強すぎる。
    ///
    /// 半透明の黄色。**不透明にしない。** 地の色と混ぜることで、
    /// 項目の文字色に手を入れずに読める濃さに収まる（ダークで 4.99、ライトで 15 以上）。
    public var outlineSelection: PlatformColor { searchMatch.withAlphaComponent(0.28) }

    /// 目次から飛んだ行を光らせる色。`progress` は 1 から 0 へ落ちる。
    ///
    /// **濃さを外観ごとに変えている。** 黄色はもともと明るいので、
    /// ダークで同じ濃さにすると本文の白い文字とのコントラストが 3.3 まで落ちる。
    /// ライト 0.55 / ダーク 0.35 で、どちらも見出しの文字が読める
    /// （ライト 15 以上、ダーク 4.96）。
    ///
    /// 半透明のまま地の色と混ぜるので、**文字色には触らなくてよい。**
    /// 触ると、薄れていく途中で元の色へ戻す処理が要る。
    public func jumpFlash(progress: CGFloat) -> PlatformColor {
        let level = max(0, min(1, progress))
        return .dynamic(
            light: .rgb(255, 214, 10).withAlphaComponent(0.55 * level),
            dark: .rgb(255, 214, 10).withAlphaComponent(0.35 * level)
        )
    }

    // MARK: - プレビューのインラインコード

    // プレビューだけ、インラインコード（`` `code` ``）を角丸の札として描く。
    // **編集画面はこの色を使わない。** あちらは記法文字（バッククォート）が見えている
    // ぶん、地の色をうっすら変えるだけで十分に区別が付く。
    // プレビューは記法文字が消えるので、輪郭のある札にしないと本文に埋もれる。

    // 色は1つずつ作り置きする。呼ぶたびに作ると、文字の並びの数だけ
    // 動的な色が生まれるうえ、同じ色かどうかを同一性で比べられなくなる。

    /// 札の中の文字。ライトは黒、ダークは白。
    public var inlineCodeText: PlatformColor { Self.inlineCodeTextColor }
    /// 札の地。
    public var inlineCodeBackground: PlatformColor { Self.inlineCodeBackgroundColor }
    /// 札の枠線。ライトは薄い灰、ダークは薄い白。
    ///
    /// ライトは地と背景の差が 1.06 しかないので、線が無いと札の形が分からない。
    /// ダークは地だけでも浮く（1.65）が、線を入れると縁が締まる。
    /// **ダークは不透明な白にしない。** 地より明るい線が主張しすぎる。
    public var inlineCodeBorder: PlatformColor { Self.inlineCodeBorderColor }

    private static let inlineCodeTextColor: PlatformColor =
        .dynamic(light: .rgb(28, 28, 30), dark: .rgb(255, 255, 255))
    private static let inlineCodeBackgroundColor: PlatformColor =
        .dynamic(light: .rgb(237, 237, 241), dark: .rgb(71, 83, 91))
    private static let inlineCodeBorderColor: PlatformColor =
        .dynamic(light: .rgb(192, 192, 200), dark: .rgb(255, 255, 255).withAlphaComponent(0.22))

    /// 札の角の丸み。**丸めすぎない。** 角丸が大きいと薬のカプセルのようになり、
    /// 文中に置いたときボタンと見分けが付かなくなる。
    public var inlineCodeCornerRadius: CGFloat { (fontSize * 0.20).rounded() }

    /// 札の中の左右の余白。同じ幅だけ、隣の文字との間もあける。
    public var inlineCodePadding: CGFloat { (fontSize * 0.30).rounded() }

    /// 札の高さ。行の高さではなく文字の大きさから決める。
    public var inlineCodeHeight: CGFloat { (fontSize * 1.55).rounded() }

    /// 表の見出し行の背景。本文の背景から一段ずらして、見出しだと分かるようにする。
    ///
    /// いまはコードブロックの背景と同じ値。役割が違うので名前は分けてある
    /// （どちらかだけ変えたくなったときに困らない）。
    public var tableHeaderBackground: PlatformColor { codeBackground }

    /// 表の罫線。
    public var tableBorder: PlatformColor { marker.withAlphaComponent(0.45) }

    /// ボタンやトグルが「オン」のときの色。
    ///
    /// **OS のアクセントカラーに従わせない。** 利用者の設定しだいで
    /// 目次・検索・プレビューのボタンの色が変わってしまい、
    /// 配色を1組に決めている意味が薄れる。
    ///
    /// いまは検索のヒットと同じ黄色。役割が違うので名前は分けてある
    /// （どちらかだけ変えたくなったときに困らない）。
    public var control: PlatformColor { searchMatch }

    /// 今カーソルがある行の番号に使う色。
    ///
    /// **かつては OS のハイライト／アクセント設定に従わせていた。**
    /// 「今どこにいるか」を OS の選択表示と揃える意図だったが、
    /// 利用者の設定しだいで読めない色にもなり得るのをやめ、配色表に取り込んだ。
    ///
    /// ライトでは暗い琥珀、ダークでは `control` と同じ黄色。**同じ値にはできない。**
    /// `#FFD60A` は文字色として置くとライトの背景（#F5F5F5）との比が 1.29 しかなく読めない
    /// （システム色を使っていた頃に踏んだ B-10 と同じ罠）。
    public var activeLineNumber: PlatformColor {
        .dynamic(light: .rgb(126, 96, 0), dark: .rgb(255, 214, 10))
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
            accent: .dynamic(light: .rgb(0, 128, 255), dark: .rgb(0, 128, 255)),
            // ヒットは**ライトとダークで同じ色**にする。文字の方を暗い色で固定した以上、
            // 外観ごとに変える理由が無い。地の色（薄い灰／濃い青灰）のどちらに対しても
            // 十分に浮く、彩度の高い黄と橙を選んである。
            searchMatch: .rgb(255, 214, 10),
            searchCurrentMatch: .rgb(255, 149, 0),
            searchMatchText: .rgb(28, 28, 30)
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
