import Testing
@testable import MarkdownCore

/// 3つの版の突き合わせ。
///
/// **黙って間違えるのがいちばん怖い。**
/// 「合流してよいのに競合にした」は直せばよいが、
/// 「競合なのに片方を捨てた」は書きかけが消える。後者を重点的に縛る。
@Suite("3つの版の突き合わせ")
struct ThreeWayMergeTests {

    func merge(_ base: String, ours: String, theirs: String) -> ThreeWayMerge.Result {
        ThreeWayMerge.merge(base: base, ours: ours, theirs: theirs)
    }

    // MARK: - 黙って合流できる場合

    @Test("片方しか触っていなければ、そちらを採る")
    func onlyOneSideChanged() {
        let base = "あ\nい\nう\n"
        #expect(merge(base, ours: base, theirs: "あ\nい\nう\nえ\n").text == "あ\nい\nう\nえ\n")
        #expect(merge(base, ours: "あ\nい\nう\nえ\n", theirs: base).text == "あ\nい\nう\nえ\n")
    }

    @Test("離れた行を直していれば、両方取り込む")
    func mergesDisjointEdits() {
        // これがいちばん多い場面。Claude Code が別の節を書き換え、
        // こちらは手元で別の行を直している。
        let result = merge(
            "1行目\n2行目\n3行目\n4行目\n5行目\n",
            ours:   "1行目を直した\n2行目\n3行目\n4行目\n5行目\n",
            theirs: "1行目\n2行目\n3行目\n4行目\n5行目を直した\n"
        )
        #expect(result.text == "1行目を直した\n2行目\n3行目\n4行目\n5行目を直した\n")
        #expect(result.hasConflicts == false)
    }

    /// **隣り合う行でも競合させない。**
    ///
    /// 以前は「3つの版が揃う行」で区間を切っていたため、触った行が隣り合うと
    /// あいだに目印が無く、まとめて1つの競合になっていた。
    /// いまは基準に対する**編集の範囲が重なるか**で見る（D-34）。
    @Test("隣り合う行を別々に直しても、競合にしない")
    func adjacentLinesChanged() {
        let result = merge("あ\nい\nう\n", ours: "あ\nい\nう2\n", theirs: "あ\nい2\nう\n")
        #expect(result.text == "あ\nい2\nう2\n")
        #expect(!result.hasConflicts)
    }

    /// 箇条書きでいちばん起きる形。相手が直した行の**真下**に足す。
    @Test("相手が直した行の真下に足しても、競合にしない")
    func insertBelowChangedLine() {
        let result = merge(
            "- A\n- B\n",
            ours: "- A\n- 足した\n- B\n",
            theirs: "- A を直した\n- B\n"
        )
        #expect(result.text == "- A を直した\n- 足した\n- B\n")
        #expect(!result.hasConflicts)
    }

    /// **同じ行に二人が書き足したら、どちらを先に置くか決められない。**
    /// ここは印を出す。合流の緩さは、ここまで。
    @Test("同じ行に二人が書き足したら印を付ける")
    func sameLineAppended() {
        let result = merge("- A\n", ours: "- A こちら\n", theirs: "- A むこう\n")
        #expect(result.conflictCount == 1)
        #expect(result.text.contains("- A こちら"))
        #expect(result.text.contains("- A むこう"))
    }

    /// **相手がこちらの直しを読んでから書いた場合。**
    ///
    /// 外から書く道具は、書く直前にファイルを読む（`Tools/mdmerge`）。
    /// その版にはこちらの直しがそのまま入っているので、印を出す理由が無い。
    @Test("相手の版にこちらの直しが入っていれば、競合にしない")
    func theirsAlreadyContainsOurs() {
        let result = merge(
            "- A\n- B\n",
            ours: "- A 直した\n- B\n",
            theirs: "- A 直した\n- B 相手が足した\n"
        )
        #expect(result.text == "- A 直した\n- B 相手が足した\n")
        #expect(!result.hasConflicts)
    }

    @Test("こちらの版に相手の直しが入っていれば、競合にしない")
    func oursAlreadyContainsTheirs() {
        let result = merge(
            "- A\n- B\n",
            ours: "- A 直した\n- B こちらが足した\n",
            theirs: "- A 直した\n- B\n"
        )
        #expect(result.text == "- A 直した\n- B こちらが足した\n")
        #expect(!result.hasConflicts)
    }

    @Test("同じ直し方をしていれば競合にしない")
    func identicalEditsAreNotConflicts() {
        let result = merge("あ\nい\n", ours: "あ\nいい\n", theirs: "あ\nいい\n")
        #expect(result.text == "あ\nいい\n")
        #expect(result.hasConflicts == false)
    }

    @Test("どちらも触っていなければそのまま")
    func noChanges() {
        let base = "あ\nい\n"
        let result = merge(base, ours: base, theirs: base)
        #expect(result.text == base)
        #expect(result.hasConflicts == false)
    }

    @Test("それぞれ別の場所に行を足す")
    func insertionsAtDifferentPlaces() {
        let result = merge(
            "見出し\n\n本文\n",
            ours:   "見出し\n\n自分が足した行\n本文\n",
            theirs: "見出し\n\n本文\n外が足した行\n"
        )
        #expect(result.hasConflicts == false)
        #expect(result.text.contains("自分が足した行"))
        #expect(result.text.contains("外が足した行"))
    }

    // MARK: - 競合として印を付ける場合

    @Test("同じ行を別々に直したら印を付ける")
    func conflictingEditsAreMarked() {
        let result = merge("あ\nい\nう\n", ours: "あ\n自分の直し\nう\n", theirs: "あ\n外の直し\nう\n")

        #expect(result.conflictCount == 1)
        #expect(result.text == """
        あ
        \(ThreeWayMerge.ourMarker)
        自分の直し
        \(ThreeWayMerge.separator)
        外の直し
        \(ThreeWayMerge.theirMarker)
        う

        """)
    }

    /// **印は食い違っているところだけを囲む。**
    ///
    /// 二人が同じ行を同じように直していると、古い基準から見れば
    /// どちらも「変えた」ことになり、同じ塊に入る。
    /// そのまま囲むと、同じ行が印の上下に並んで読めない（実機で確認。D-35）。
    @Test("両側で一致している行は、印の外に出す")
    func conflictIsTrimmedToTheDifference() {
        let result = merge(
            "A\nB\nC\n",
            ours:   "A\nB こちら\nC 二人とも同じ\n",
            theirs: "A\nB むこう\nC 二人とも同じ\n"
        )
        #expect(result.conflictCount == 1)
        let lines = result.text.components(separatedBy: "\n")
        // 一致している C 行は、印の外に1回だけ。
        #expect(lines.filter { $0 == "C 二人とも同じ" }.count == 1)
        #expect(lines.last(where: { !$0.isEmpty }) == "C 二人とも同じ")
        // 食い違う B 行だけが印の中。
        guard let ourMark = lines.firstIndex(of: ThreeWayMerge.ourMarker),
              let separator = lines.firstIndex(of: ThreeWayMerge.separator),
              let theirMark = lines.firstIndex(of: ThreeWayMerge.theirMarker)
        else {
            Issue.record("印が見つからない")
            return
        }
        #expect(Array(lines[(ourMark + 1)..<separator]) == ["B こちら"])
        #expect(Array(lines[(separator + 1)..<theirMark]) == ["B むこう"])
    }

    @Test("印を付けても、どちらの内容も消さない")
    func conflictKeepsBothSides() {
        // **ここが要。** 片方でも落ちたら、書きかけが消えたことになる。
        let result = merge(
            "もとの行\n",
            ours: "自分の大事な書きかけ\n",
            theirs: "外で書かれた内容\n"
        )
        #expect(result.text.contains("自分の大事な書きかけ"))
        #expect(result.text.contains("外で書かれた内容"))
        #expect(result.hasConflicts)
    }

    @Test("離れた2か所がぶつかれば、印も2つ")
    func multipleConflicts() {
        let result = merge(
            "1\n2\n3\n4\n5\n",
            ours:   "自分1\n2\n3\n4\n自分5\n",
            theirs: "外1\n2\n3\n4\n外5\n"
        )
        #expect(result.conflictCount == 2)
    }

    @Test("片方が消した行を、もう片方が直していたら印を付ける")
    func deleteVersusEdit() {
        // 消すか残すかは機械には決められない。
        let result = merge("あ\n消される行\nう\n", ours: "あ\nう\n", theirs: "あ\n直された行\nう\n")
        #expect(result.hasConflicts)
        #expect(result.text.contains("直された行"))
    }

    @Test("文書を丸ごと書き換えられたら、全体を1つの競合にする")
    func completelyDifferentContents() {
        let result = merge(
            "もとの文書\n",
            ours: "自分が全部書き直した\n",
            theirs: "外が全部書き直した\n"
        )
        #expect(result.hasConflicts)
        #expect(result.text.contains("自分が全部書き直した"))
        #expect(result.text.contains("外が全部書き直した"))
    }

    // MARK: - 改行の扱い

    @Test("末尾の改行の有無が変わらない")
    func preservesTrailingNewline() {
        // 改行が1つ増減するだけで、ファイル全体の差分に出る。
        #expect(merge("あ\n", ours: "あ\n", theirs: "あ\n").text == "あ\n")
        #expect(merge("あ", ours: "あ", theirs: "あ").text == "あ")
        #expect(merge("あ\nい\n", ours: "あ\nい\n", theirs: "あ\nい\nう\n").text == "あ\nい\nう\n")
    }

    @Test("空の文書でも落ちない")
    func emptyDocuments() {
        #expect(merge("", ours: "", theirs: "").text == "")
        #expect(merge("", ours: "", theirs: "外で書かれた\n").text == "外で書かれた\n")
        #expect(merge("あ\n", ours: "", theirs: "あ\n").text == "")
    }

    // MARK: - 大きさ

    @Test("長い文書でも、直した数行だけを見る")
    func handlesLongDocuments() {
        // 先頭と末尾の一致を先に落とすので、行数が増えても素早く終わる。
        let lines = (1...3000).map { "行 \($0)" }
        let base = lines.joined(separator: "\n") + "\n"
        var ourLines = lines
        ourLines[10] = "自分が直した行"
        var theirLines = lines
        theirLines[2000] = "外が直した行"

        let result = merge(
            base,
            ours: ourLines.joined(separator: "\n") + "\n",
            theirs: theirLines.joined(separator: "\n") + "\n"
        )
        #expect(result.hasConflicts == false)
        #expect(result.text.contains("自分が直した行"))
        #expect(result.text.contains("外が直した行"))
    }
}
