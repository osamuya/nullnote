import SwiftUI

// 図が描き終わったことを、プレビューへ伝える細い口。
//
// **スクロール同期は一度しか走らない。** エディタの先頭行が変わった時点で
// 「その行を含むブロックを上端へ」送るが、**そのとき図はまだ描かれていない。**
// 中身が短いので送り先が頭打ちになり、図より下のブロックへは届かない
// （実測：69 行目（`# hoge`）に合わせても位置 601pt のまま。送れる上限は 1095pt で、
// 494pt 届いていなかった）。
//
// 図が高さを決めた時点でここを叩き、プレビューが同期を送り直す。

private struct DiagramRenderedKey: EnvironmentKey {
    /// 既定は何もしない。プレビューの外に置かれたときは、ただ無視される。
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    /// 図が高さを決めたときに呼ぶ。
    var onDiagramRendered: @MainActor () -> Void {
        get { self[DiagramRenderedKey.self] }
        set { self[DiagramRenderedKey.self] = newValue }
    }
}
