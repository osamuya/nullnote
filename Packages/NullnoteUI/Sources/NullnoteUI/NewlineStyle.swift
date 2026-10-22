import Foundation

/// プレビューで、普通の改行（行末に半角スペース2つが無いもの）をどう読むか。
///
/// **本文は書き換えない。** 読み方を変えるだけなので、切り替えはいつでも効く（D-33）。
///
/// 日本語の文章は改行1つで段落を終えるが、Markdown では改行1つは同じ段落の続きになる。
/// どちらの書き方の文書も読めるように、3つから選ぶ（D-74）。
public enum NewlineStyle: String, CaseIterable, Identifiable, Sendable {
    /// CommonMark どおり、前の行につなげる。
    case markdown
    /// 段落の中で折り返す。D-33 の設定を入れたときと同じ。
    case lineBreak
    /// 段落を終える。行末の半角スペース2つも同じく段落を分ける。
    ///
    /// 分けるのは文書の一番外の段落だけ。リスト・引用の中は `lineBreak` と同じにする。
    case paragraph

    public var id: String { rawValue }

    /// 設定画面に出す名前。`MarkdownAppearance.label` と同じ理由で `String` にしない。
    ///
    /// 文化に寄せず、何が起きるかで書く（7つの言語で出すため）。
    public var label: LocalizedStringResource {
        switch self {
        case .markdown: LocalizedStringResource("Markdown どおり", bundle: .module)
        case .lineBreak: LocalizedStringResource("改行で折り返す", bundle: .module)
        case .paragraph: LocalizedStringResource("改行で段落を分ける", bundle: .module)
        }
    }
}
