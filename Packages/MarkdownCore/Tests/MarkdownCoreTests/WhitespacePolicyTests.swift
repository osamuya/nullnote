import Testing
@testable import MarkdownCore

@Suite("空白の違いを無視する合流")
struct WhitespacePolicyTests {

    // MARK: - 比べ方そのもの

    @Test("行の途中の空白の量は無視する")
    func innerRuns() {
        let policy = WhitespacePolicy.ignoreInnerRuns
        #expect(policy.equal("# here", "#  here"))
        #expect(policy.equal("- a | b", "- a  |  b"))
        #expect(policy.equal("foo\tbar", "foo bar"))
    }

    /// **Markdown では行頭と行末の空白が意味を持つ。**
    /// 入れ子の深さと、行末2つによる改行。だから残す。
    @Test("行頭のインデントは区別する")
    func leadingIsKept() {
        let policy = WhitespacePolicy.ignoreInnerRuns
        #expect(!policy.equal("  - item", "    - item"))
        #expect(!policy.equal("- item", "  - item"))
    }

    @Test("行末の空白も区別する")
    func trailingIsKept() {
        let policy = WhitespacePolicy.ignoreInnerRuns
        #expect(!policy.equal("foo  ", "foo"))
        #expect(!policy.equal("foo  ", "foo "))
    }

    @Test("空白を挟むかどうかは区別する（量だけを無視する）")
    func presenceIsKept() {
        let policy = WhitespacePolicy.ignoreInnerRuns
        // `#here` は見出しではない。同じにしてはいけない。
        #expect(!policy.equal("# here", "#here"))
        #expect(!policy.equal("- item", "-item"))
    }

    @Test("strict は1文字でも違えば違う")
    func strict() {
        #expect(!WhitespacePolicy.strict.equal("# here", "#  here"))
        #expect(WhitespacePolicy.strict.equal("# here", "# here"))
    }

    // MARK: - 合流での効き方

    @Test("空白の量だけの食い違いなら、印を出さない")
    func noConflictOnWhitespace() {
        let result = ThreeWayMerge.merge(
            base: "# here\n本文",
            ours: "# here!\n本文",
            theirs: "#  here!\n本文"
        )
        #expect(!result.hasConflicts)
    }

    @Test("strict なら、同じ場面で印が出る")
    func strictConflicts() {
        let result = ThreeWayMerge.merge(
            base: "# here\n本文",
            ours: "# here!\n本文",
            theirs: "#  here!\n本文",
            whitespace: .strict
        )
        #expect(result.hasConflicts)
    }

    @Test("中身が違えば、空白を無視しても印は出る")
    func realConflictSurvives() {
        let result = ThreeWayMerge.merge(
            base: "# here",
            ours: "# there",
            theirs: "#  everywhere"
        )
        #expect(result.hasConflicts)
    }

    /// 入れ子の深さは意味が違う。**無視してはいけない。**
    @Test("入れ子の深さが違えば、印が出る")
    func indentConflicts() {
        let result = ThreeWayMerge.merge(
            base: "- item",
            ours: "  - item",
            theirs: "    - item"
        )
        #expect(result.hasConflicts)
    }

    @Test("採られた側の本文は、書かれたとおりに残る")
    func textIsNotRewritten() {
        // 外だけが空白を増やした。こちらは触っていない。
        let result = ThreeWayMerge.merge(
            base: "# here",
            ours: "# here",
            theirs: "#  here"
        )
        #expect(!result.hasConflicts)
        // **詰めたり整えたりしない。** どちらかの原文がそのまま出る。
        #expect(result.text == "# here" || result.text == "#  here")
    }
}
