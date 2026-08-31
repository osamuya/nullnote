import Foundation

/// 選んだところを記法で囲む。
///
/// **副作用を持たない。** 何をどう書き換えるかだけを決める。
/// 実際に本文を触るのは呼ぶ側（`FocusReportingTextView`）。
///
/// ## 2つの入口
///
/// | | |
/// |---|---|
/// | 記号キー | 選んだ状態で `*` `` ` `` `~` `[` を押す |
/// | ショートカット | ⌘B（太字）、⌘I（斜体）、⌘K（リンク） |
///
/// **中身は同じ。** 入口が違うだけ。
///
/// ## 決めたこと（2026-08-31）
///
/// **打った瞬間に閉じを入れる形（`**` と打ったら `**|**`）は入れない。**
/// 打ち消しの手当て（自分で閉じを打ったとき乗り越える、⌫ で対を消す）が要り、
/// 片方だけ作るとかえって煩わしい。日本語入力ともぶつかる。
/// **選択という、はっきりした合図があるときにだけ動く**方が事故が無い。
public enum InlineWrap {

    /// 囲み方。
    public struct Style: Equatable, Sendable {
        /// 前に置く文字列。
        public let opening: String
        /// 後ろに置く文字列。
        public let closing: String
        /// 囲んだあと、カーソルを閉じの**後ろ**へ動かすか。
        /// リンクだけは `](` の中（行き先の位置）へ入れたいので `false`。
        public let caretAfterClosing: Bool

        public init(opening: String, closing: String, caretAfterClosing: Bool = true) {
            self.opening = opening
            self.closing = closing
            self.caretAfterClosing = caretAfterClosing
        }

        /// `**太字**`
        public static let strong = Style(opening: "**", closing: "**")
        /// `*斜体*`
        public static let emphasis = Style(opening: "*", closing: "*")
        /// `` `コード` ``
        public static let code = Style(opening: "`", closing: "`")
        /// `~取り消し~`
        public static let strikethrough = Style(opening: "~", closing: "~")
        /// `[文字]`
        public static let bracket = Style(opening: "[", closing: "]")
        /// `[文字](…)`。**カーソルは行き先の位置に置く。**
        public static let link = Style(opening: "[", closing: "]()", caretAfterClosing: false)
    }

    /// 記号キーに対応する囲み方。**ここに無いキーは、ふつうに文字が入る。**
    ///
    /// `_` を入れていないのは、`snake_case` を打つ場面とぶつかるため。
    /// `(` や `"` も、ふつうに打ちたい場面が多いので外している。
    public static func style(forTypedCharacter character: String) -> Style? {
        switch character {
        case "*": .emphasis
        case "`": .code
        case "~": .strikethrough
        case "[": .bracket
        default: nil
        }
    }

    /// 書き換えの中身。
    public struct Result: Equatable {
        /// 選んだところに置き換わる文字列。
        public let text: String
        /// 置き換えたあと、**その文字列の先頭から数えた**カーソルの位置（UTF-16）。
        public let caretOffset: Int
        /// 囲んだ中身を選び直す長さ。0 なら選択せずカーソルだけ置く。
        public let selectionLength: Int
    }

    /// 選んだ文字を囲む。
    ///
    /// - Parameter selected: 選んでいる文字。空なら「選択が無い」とみなし、
    ///   記法だけを置いてカーソルをあいだに入れる。
    public static func wrap(_ selected: String, with style: Style) -> Result {
        let text = style.opening + selected + style.closing

        // リンクは行き先の位置（`](` の中）へ。それ以外は閉じの後ろへ。
        guard style.caretAfterClosing else {
            // `[文字](` までの長さ。`]()` の `(` の直後に置く。
            let offset = (style.opening + selected).utf16.count + 2
            return Result(text: text, caretOffset: offset, selectionLength: 0)
        }

        if selected.isEmpty {
            // 記法だけ置いて、あいだで打てるようにする。
            return Result(
                text: text, caretOffset: style.opening.utf16.count, selectionLength: 0
            )
        }
        // 囲んだ中身を選んだままにする。続けて重ねがけできる（`*` をもう一度で `**`）。
        return Result(
            text: text,
            caretOffset: style.opening.utf16.count,
            selectionLength: selected.utf16.count
        )
    }
}
