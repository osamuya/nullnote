import Testing
@testable import mdmerge

/// 外から書く側が、相手の直しを踏み潰さないこと。
///
/// アプリ側（`ExternalChangeResolver`）は「編集画面とディスク」の話だが、
/// こちらは**メモリ上の版を持たない側**の話。基準は「自分が読んだ時点の内容」になる。
@Suite("書く前の合流")
struct MergeWriteTests {

    @Test("誰も触っていなければ、そのまま書く")
    func noOneElseTouched() {
        let plan = MergeWrite.plan(base: "A\nB\n", ours: "A\nB2\n", theirs: "A\nB\n")
        #expect(plan.text == "A\nB2\n")
        #expect(plan.conflictCount == 0)
        #expect(plan.needsWrite)
    }

    @Test("離れた行を直していれば、黙って両方残る")
    func differentLinesMerge() {
        let plan = MergeWrite.plan(
            base:   "A\nB\nC\nD\n",
            ours:   "A\nB\nC\nD2\n",   // こちらは D を直した
            theirs: "A\nB2\nC\nD\n"    // 相手は B を直した
        )
        #expect(plan.text == "A\nB2\nC\nD2\n")
        #expect(plan.conflictCount == 0)
        #expect(plan.needsWrite)
    }

    @Test("隣り合う行を別々に直しても、競合しない")
    func adjacentLinesMerge() {
        let plan = MergeWrite.plan(
            base:   "A\nB\nC\n",
            ours:   "A\nB\nC2\n",
            theirs: "A\nB2\nC\n"
        )
        #expect(plan.text == "A\nB2\nC2\n")
        #expect(plan.conflictCount == 0)
    }

    /// 箇条書きでいちばん起きる形。
    /// 相手が直した行の**真下**に、こちらが1行足す。
    @Test("相手が直した行の真下に足しても、競合しない")
    func insertBelowTheirEdit() {
        let plan = MergeWrite.plan(
            base:   "- [#016] X\n- [#015] Y\n",
            ours:   "- [#016] X\n- [#017] 新\n- [#015] Y\n",
            theirs: "- [#016] X 直した\n- [#015] Y\n"
        )
        #expect(plan.text == "- [#016] X 直した\n- [#017] 新\n- [#015] Y\n")
        #expect(plan.conflictCount == 0)
    }

    /// 同じ行に二人が書き足したときは、**どちらを先に置くか決められない**。
    /// ここは印を出す。
    @Test("同じ行に二人が書き足したら、印が入る")
    func sameLineAppendConflicts() {
        let plan = MergeWrite.plan(base: "- A\n", ours: "- A こちら\n", theirs: "- A むこう\n")
        #expect(plan.conflictCount == 1)
        #expect(plan.text.contains("- A こちら"))
        #expect(plan.text.contains("- A むこう"))
    }

    @Test("同じ行を直していれば、印が入る")
    func sameLineConflicts() {
        let plan = MergeWrite.plan(
            base:   "A\nB\n",
            ours:   "A\nB-こちら\n",
            theirs: "A\nB-むこう\n"
        )
        #expect(plan.conflictCount == 1)
        #expect(plan.text.contains(ThreeWayMergeMarkers.ours))
        #expect(plan.text.contains("B-こちら"))
        #expect(plan.text.contains("B-むこう"))
        #expect(plan.needsWrite)
    }

    @Test("こちらが何も直していなければ、相手の内容を残して書かない")
    func weChangedNothing() {
        let plan = MergeWrite.plan(base: "A\nB\n", ours: "A\nB\n", theirs: "A\nB2\n")
        #expect(plan.text == "A\nB2\n")
        #expect(!plan.needsWrite)
    }

    @Test("結果がディスクと同じなら書かない")
    func sameResultDoesNotWrite() {
        // 相手が、こちらと同じ直しを先に入れていた。
        let plan = MergeWrite.plan(base: "A\nB\n", ours: "A\nB2\n", theirs: "A\nB2\n")
        #expect(plan.text == "A\nB2\n")
        #expect(!plan.needsWrite)
    }

    @Test("相手が足した行と、こちらが足した行が、どちらも残る")
    func bothAppend() {
        let plan = MergeWrite.plan(
            base:   "# 見出し\n\n- A\n",
            ours:   "# 見出し\n\n- A\n- こちらが足した\n",
            theirs: "# 見出し\n\n- A\n"
        )
        #expect(plan.text.contains("- こちらが足した"))
        #expect(plan.conflictCount == 0)
    }
}

/// テストから印の綴りを直書きしないための入口。
enum ThreeWayMergeMarkers {
    static let ours = "<<<<<<< 自分の更新"
}
