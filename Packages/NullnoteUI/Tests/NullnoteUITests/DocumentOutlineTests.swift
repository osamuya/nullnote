import Foundation
import Testing
@testable import NullnoteUI

@Suite("目次の組み立て")
struct DocumentOutlineTests {

    // MARK: - 基本

    @Test("見出しが無ければ空")
    func noHeadings() {
        #expect(DocumentOutline.build(from: "本文だけです。\n\n- 箇条書き\n").isEmpty)
        #expect(DocumentOutline.build(from: "").isEmpty)
    }

    @Test("同じレベルの見出しは並ぶ")
    func sameLevel() {
        let outline = DocumentOutline.build(from: "# A\n\n# B\n\n# C")
        #expect(outline.map(\.title) == ["A", "B", "C"])
        #expect(outline.allSatisfy { $0.children == nil })
    }

    @Test("深い見出しは子になる")
    func nesting() {
        let source = """
        # 第1章

        ## 1-1

        ## 1-2

        # 第2章
        """
        let outline = DocumentOutline.build(from: source)
        #expect(outline.map(\.title) == ["第1章", "第2章"])
        #expect(outline[0].children?.map(\.title) == ["1-1", "1-2"])
        #expect(outline[1].children == nil)
    }

    @Test("3階層まで入れ子になる")
    func deepNesting() {
        let source = "# A\n\n## B\n\n### C\n\n### D\n\n## E"
        let outline = DocumentOutline.build(from: source)
        #expect(outline.count == 1)
        let b = outline[0].children?[0]
        #expect(b?.title == "B")
        #expect(b?.children?.map(\.title) == ["C", "D"])
        #expect(outline[0].children?[1].title == "E")
    }

    // MARK: - 行番号

    @Test("元の行番号を持つ")
    func lineNumbers() {
        let source = """
        # 1行目

        本文

        ## 5行目
        """
        let outline = DocumentOutline.build(from: source)
        #expect(outline[0].line == 1)
        #expect(outline[0].children?[0].line == 5)
    }

    // MARK: - 記法の除去

    @Test("見出しの中の記法文字を取り除く")
    func stripsMarkup() {
        #expect(DocumentOutline.build(from: "# **設計** の話")[0].title == "設計 の話")
        #expect(DocumentOutline.build(from: "# `コード` を書く")[0].title == "コード を書く")
        #expect(DocumentOutline.build(from: "# ~~古い~~ 新しい")[0].title == "古い 新しい")
    }

    @Test("見出しの中のリンクは表示テキストだけ残す")
    func stripsLinkMarkup() {
        #expect(DocumentOutline.build(from: "# [参考](https://example.com) の話")[0].title == "参考 の話")
    }

    @Test("末尾の閉じシーケンスは含めない")
    func closingSequence() {
        #expect(DocumentOutline.build(from: "## タイトル ##")[0].title == "タイトル")
    }

    @Test("本文の無い見出しは項目にしない")
    func emptyTitle() {
        #expect(DocumentOutline.build(from: "#").isEmpty)
        #expect(DocumentOutline.build(from: "## ").isEmpty)
    }

    @Test("強調にならない記号はそのまま残る")
    func literalAsterisks() {
        // `****` は Markdown では強調にならず、文字そのもの。
        #expect(DocumentOutline.build(from: "# ****")[0].title == "****")
    }

    // MARK: - 崩れた文書

    @Test("いきなり深い見出しから始まっても壊れない")
    func startsDeep() {
        let outline = DocumentOutline.build(from: "### 深い\n\n# 浅い")
        #expect(outline.map(\.title) == ["深い", "浅い"])
    }

    @Test("レベルが飛んでいても入れ子になる")
    func skippedLevels() {
        let outline = DocumentOutline.build(from: "# A\n\n#### D")
        #expect(outline[0].children?.map(\.title) == ["D"])
    }

    @Test("コードブロックの中の # は見出しにしない")
    func headingInsideCodeBlock() {
        let source = """
        # 本物

        ```
        # 偽物
        ```
        """
        #expect(DocumentOutline.build(from: source).map(\.title) == ["本物"])
    }

    // MARK: - 補助

    @Test("平たくすると全部の項目が数えられる")
    func flattened() {
        let outline = DocumentOutline.build(from: "# A\n\n## B\n\n### C\n\n# D")
        #expect(outline.flattened.map(\.title) == ["A", "B", "C", "D"])
    }

    @Test("id は重複しない")
    func uniqueIdentifiers() {
        let outline = DocumentOutline.build(from: "# A\n\n## B\n\n### C\n\n# D\n\n## E")
        let ids = outline.flattened.map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
