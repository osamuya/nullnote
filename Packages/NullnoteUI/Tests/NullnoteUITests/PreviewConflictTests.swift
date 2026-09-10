import Foundation
import MarkdownCore
import Testing
@testable import NullnoteUI

/// 合流の印を、プレビューがどう扱うか。
///
/// 印は Markdown の記法ではない。そのまま `Document(parsing:)` に渡すと
/// `=======` が下線見出しになり、`>>>>>>>` が7重の引用になる。
/// **印の周りの本文まで、実際とは違う姿で出る**（D-60）。
@Suite("プレビューの合流の印")
struct PreviewConflictTests {

    private let ours = ThreeWayMerge.ourMarker
    private let separator = ThreeWayMerge.separator
    private let theirs = ThreeWayMerge.theirMarker

    private func blocks(_ source: String) -> [PreviewBlock] {
        PreviewBuilder.build(source, theme: .standard())
    }

    private func firstConflict(_ source: String) -> PreviewConflict? {
        for block in blocks(source) {
            if case .conflict(let conflict) = block.content { return conflict }
        }
        return nil
    }

    /// 報告のあった本文そのまま。
    private var reported: String {
        """
        \(ours)
        We test the merge.
        \(separator)
        A different program rewrote this line.
        \(theirs)
        """
    }

    @Test("印は1つの塊になる")
    func makesOneBlock() {
        let all = blocks(reported)
        #expect(all.count == 1)
        guard case .conflict = all.first?.content else {
            Issue.record("合流の印として取れていない")
            return
        }
    }

    @Test("`=======` が上の行を見出しに変えない")
    func separatorDoesNotMakeHeading() throws {
        // これが報告の本題。`=======` は setext の下線として解釈され、
        // 直前の段落が見出しに化けていた。
        let conflict = try #require(firstConflict(reported))
        guard case .paragraph(let text) = conflict.ours.first?.content else {
            Issue.record("自分の版が段落として取れていない")
            return
        }
        #expect(String(text.characters) == "We test the merge.")
    }

    @Test("`>>>>>>>` が引用にならない")
    func theirMarkerDoesNotMakeQuote() throws {
        let conflict = try #require(firstConflict(reported))
        guard case .paragraph(let text) = conflict.theirs.first?.content else {
            Issue.record("外の版が段落として取れていない")
            return
        }
        #expect(String(text.characters) == "A different program rewrote this line.")
        // 引用の縦棒が7本並んでいた。
        #expect(!blocks(reported).contains { if case .quote = $0.content { true } else { false } })
    }

    @Test("印そのものは本文に出ない")
    func markersAreNotShown() {
        let text = blocks(reported)
            .compactMap { block -> String? in
                if case .conflict(let conflict) = block.content {
                    return (conflict.ours + conflict.theirs).compactMap {
                        if case .paragraph(let text) = $0.content { String(text.characters) } else { nil }
                    }.joined(separator: "\n")
                }
                return nil
            }
            .joined()
        #expect(!text.contains("<<<<<<<"))
        #expect(!text.contains("======="))
        #expect(!text.contains(">>>>>>>"))
    }

    @Test("中身は Markdown として組まれる")
    func bodiesAreParsed() throws {
        let conflict = try #require(firstConflict("""
        \(ours)
        ## 見出し
        \(separator)
        - 箇条書き
        \(theirs)
        """))
        guard case .heading(let level, _) = conflict.ours.first?.content else {
            Issue.record("自分の版の見出しが組まれていない")
            return
        }
        #expect(level == 2)
        guard case .list = conflict.theirs.first?.content else {
            Issue.record("外の版のリストが組まれていない")
            return
        }
    }

    @Test("片側が空でも取れる")
    func handlesEmptySide() throws {
        // 外だけが書き足した競合。描く側は「（この版では空）」と出す。
        let conflict = try #require(firstConflict("\(ours)\n\(separator)\n足された行\n\(theirs)"))
        #expect(conflict.ours.isEmpty)
        #expect(conflict.theirs.count == 1)
    }

    @Test("印の前後の本文は、これまでどおり組まれる")
    func keepsSurroundingText() {
        let all = blocks("""
        # 前置き

        \(ours)
        A
        \(separator)
        B
        \(theirs)

        あとがき
        """)
        guard case .heading = all.first?.content else {
            Issue.record("前の見出しが消えている")
            return
        }
        guard case .paragraph(let last) = all.last?.content else {
            Issue.record("あとの段落が消えている")
            return
        }
        #expect(String(last.characters) == "あとがき")
    }

    @Test("行番号は元の本文のものになる")
    func keepsSourceLines() {
        // エディタとのスクロール同期がここに乗っている。
        // 断片ごとに組む以上、行番号を足し直さないとずれる。
        let all = blocks("""
        # 前置き

        \(ours)
        A
        \(separator)
        B
        \(theirs)

        あとがき
        """)
        #expect(all.first?.sourceLine == 1, "見出しは1行目")
        #expect(all.dropFirst().first?.sourceLine == 3, "印は3行目から始まる")
        #expect(all.last?.sourceLine == 9, "あとがきは9行目")
    }

    @Test("閉じていない印は、これまでどおり本文として出る")
    func unclosedStaysAsText() {
        // 書きかけの `<<<<<<<` を打っただけで本文が消えたように見えては困る。
        let all = blocks("\(ours)\nA\n\(separator)\nB")
        #expect(!all.contains { if case .conflict = $0.content { true } else { false } })
    }

    @Test("印が2つあれば、2つとも塊になる")
    func handlesSeveral() {
        let all = blocks("""
        \(ours)
        A
        \(separator)
        B
        \(theirs)

        あいだ

        \(ours)
        C
        \(separator)
        D
        \(theirs)
        """)
        let conflicts = all.filter { if case .conflict = $0.content { true } else { false } }
        #expect(conflicts.count == 2)
    }
}
