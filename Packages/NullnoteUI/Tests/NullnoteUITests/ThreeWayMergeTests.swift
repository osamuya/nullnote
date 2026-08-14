import Testing
@testable import NullnoteUI

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
