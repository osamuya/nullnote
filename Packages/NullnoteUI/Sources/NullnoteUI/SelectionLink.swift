import Foundation

/// 編集画面とプレビューの選択の行き来（#M0045）。
///
/// 片方で文字を選ぶと、もう片方の同じ文字に色を付ける。**相手側の選択は動かさない。**
/// 相手側まで選択にすると、⌘C でどちらが写されるのか分からなくなる。
///
/// 範囲はどれも本文の UTF-16 の位置。プレビューの中の位置への読み替えは、
/// プレビューのテキストビューがそれぞれ受け持つ（`PreviewSourceIndex`）。
///
/// 画面から切り離してあるのは、付ける・消すの決まりをテストで縛るため。
public struct SelectionLink: Equatable, Sendable {

    /// 編集画面に「この範囲が見えるところまで送って」という依頼。
    public struct EditorReveal: Equatable, Sendable {
        public let range: NSRange
        private let id = UUID()
        init(range: NSRange) { self.range = range }
    }

    /// プレビューに「この行のブロックが見えるところまで送って」という依頼。
    public struct PreviewReveal: Equatable, Sendable {
        public let line: Int
        /// 送る元になった選択の始まり。同じところから選び直しているあいだは送り直さない。
        let start: Int
        private let id = UUID()
        init(line: Int, start: Int) {
            self.line = line
            self.start = start
        }
    }

    /// 編集画面に塗る範囲。プレビューで選んだところ。
    public private(set) var editorMarks: [NSRange] = []
    /// プレビューに塗る範囲。編集画面で選んだところ。
    public private(set) var previewMarks: [NSRange] = []
    public private(set) var editorReveal: EditorReveal?
    public private(set) var previewReveal: PreviewReveal?

    public init() {}

    /// 編集画面の選択が変わった。
    ///
    /// 選択が無くなった（クリックしてカーソルだけになった）ときは、両側の色を消す。
    /// - Parameter line: 最初の選択の始まりの行。プレビューを送る先に使う。
    public mutating func editorSelectionChanged(_ ranges: [NSRange], line: Int?) {
        editorMarks = []
        previewMarks = ranges.filter { $0.length > 0 }
        guard let first = previewMarks.first, let line else {
            previewReveal = nil
            return
        }
        // **選び始めたところが同じあいだは送り直さない。** ドラッグで選択を伸ばすたびに
        // プレビューが動くと、読んでいる場所が落ち着かない。
        if previewReveal?.start != first.location {
            previewReveal = PreviewReveal(line: line, start: first.location)
        }
    }

    /// プレビューの選択が変わった。`nil` は選択が無くなったとき。
    public mutating func previewSelectionChanged(_ range: NSRange?) {
        previewMarks = []
        guard let range, range.length > 0 else {
            editorMarks = []
            editorReveal = nil
            return
        }
        editorMarks = [range]
        if editorReveal?.range.location != range.location {
            editorReveal = EditorReveal(range: range)
        }
    }

    /// 両側の色を消す。本文が書き換わったとき、プレビューを閉じたときに呼ぶ。
    ///
    /// **本文が変わったら残さない。** プレビューは打鍵から少し遅れて組み直すので（D-6）、
    /// 残しておくとずれた場所に色が付く。
    public mutating func clear() {
        editorMarks = []
        previewMarks = []
        editorReveal = nil
        previewReveal = nil
    }
}
