import Foundation
import Testing
@testable import NullnoteUI

@Suite("プレビューの中間表現")
struct PreviewModelTests {

    func blocks(_ source: String) -> [PreviewBlock] {
        PreviewBuilder.build(source, theme: .standard())
    }

    /// 最初に見つかった指定種別のブロックを取り出す。
    func firstTable(_ source: String) -> PreviewTable? {
        for block in blocks(source) {
            if case .table(let table) = block.content { return table }
        }
        return nil
    }

    func firstList(_ source: String) -> PreviewList? {
        for block in blocks(source) {
            if case .list(let list) = block.content { return list }
        }
        return nil
    }

    // MARK: - ブロック

    @Test("見出しはレベルつきで取り出される")
    func heading() {
        guard case .heading(let level, let text) = blocks("## Title").first?.content else {
            Issue.record("見出しが取れていない")
            return
        }
        #expect(level == 2)
        #expect(String(text.characters) == "Title")
    }

    @Test("コードブロックは言語つきで取り出される")
    func codeBlock() {
        guard case .codeBlock(let code, let language) = blocks("```swift\nlet x = 1\n```").first?.content else {
            Issue.record("コードブロックが取れていない")
            return
        }
        #expect(code == "let x = 1")
        #expect(language == "swift")
    }

    @Test("引用は中のブロックを保持する")
    func quote() {
        guard case .quote(let inner) = blocks("> quoted").first?.content else {
            Issue.record("引用が取れていない")
            return
        }
        #expect(inner.count == 1)
    }

    @Test("水平線")
    func thematicBreak() {
        guard case .thematicBreak = blocks("---").first?.content else {
            Issue.record("水平線が取れていない")
            return
        }
    }

    @Test("ブロックの id は重複しない")
    func identifiersAreUnique() {
        let source = """
        # A

        - one
        - two

        > quote

        | x |
        | - |
        | 1 |
        """
        let ids = blocks(source).map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    // MARK: - GFM 拡張

    @Test("表が列の配置つきで解析される")
    func table() {
        let source = """
        | left | center | right |
        | :--- | :----: | ----: |
        | 1    | 2      | 3     |
        """
        guard let table = firstTable(source) else {
            Issue.record("表が取れていない")
            return
        }
        #expect(table.header.map { String($0.characters) } == ["left", "center", "right"])
        #expect(table.rows.count == 1)
        #expect(table.rows[0].map { String($0.characters) } == ["1", "2", "3"])

        #expect(table.alignments.count == 3)
        if case .center = table.alignments[1] {} else { Issue.record("中央揃えが取れていない") }
        if case .trailing = table.alignments[2] {} else { Issue.record("右揃えが取れていない") }
    }

    @Test("タスクリストのチェック状態が取れる")
    func taskList() {
        guard let list = firstList("- [ ] todo\n- [x] done") else {
            Issue.record("リストが取れていない")
            return
        }
        #expect(list.items.map(\.isChecked) == [false, true])
    }

    @Test("通常のリスト項目にはチェック状態が無い")
    func plainList() {
        #expect(firstList("- one\n- two")?.items.allSatisfy { $0.isChecked == nil } == true)
    }

    @Test("番号付きリストは開始番号を保持する")
    func orderedList() {
        let list = firstList("3. three\n4. four")
        #expect(list?.isOrdered == true)
        #expect(list?.start == 3)
    }

    @Test("取り消し線が装飾として載る")
    func strikethrough() {
        guard case .paragraph(let text) = blocks("~~gone~~").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        let runs = text.runs.map(\.inlinePresentationIntent)
        #expect(runs.contains { $0?.contains(.strikethrough) == true })
        // SwiftUI の Text は inlinePresentationIntent の .strikethrough を描かない。
        // 具体的な属性まで載っていること。
        #expect(text.runs.contains { $0.strikethroughStyle != nil })
    }

    // MARK: - インライン

    @Test("強調と強い強調が装飾として載る")
    func emphasisIntents() {
        guard case .paragraph(let text) = blocks("*a* **b**").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        let runs = text.runs.map(\.inlinePresentationIntent)
        #expect(runs.contains { $0?.contains(.emphasized) == true })
        #expect(runs.contains { $0?.contains(.stronglyEmphasized) == true })
    }

    @Test("入れ子の装飾は合成される")
    func nestedIntents() {
        guard case .paragraph(let text) = blocks("**bold *and italic***").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        let combined = text.runs.contains { run in
            guard let intent = run.inlinePresentationIntent else { return false }
            return intent.contains(.stronglyEmphasized) && intent.contains(.emphasized)
        }
        #expect(combined)
    }

    @Test("インラインコードは等幅の装飾になる")
    func inlineCode() {
        guard case .paragraph(let text) = blocks("`let x`").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(String(text.characters) == "let x")
        #expect(text.runs.contains { $0.inlinePresentationIntent?.contains(.code) == true })
        // 同じく .code だけでは等幅にならないので、フォントまで載っていること。
        #expect(text.runs.contains { $0.font != nil })
    }

    @Test("インラインコードのフォントはテーマの文字サイズに追従する")
    func inlineCodeFollowsThemeFontSize() {
        let large = PreviewBuilder.build("`x`", theme: .standard(fontSize: 24))
        let small = PreviewBuilder.build("`x`", theme: .standard(fontSize: 12))
        guard case .paragraph(let largeText) = large.first?.content,
              case .paragraph(let smallText) = small.first?.content
        else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(largeText.runs.first?.font != smallText.runs.first?.font)
    }

    @Test("リンクは URL を保持する")
    func link() {
        guard case .paragraph(let text) = blocks("[Apple](https://apple.com)").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(text.runs.contains { $0.link == URL(string: "https://apple.com") })
        // クリックできることを示すため、リンクには常に下線を引く。
        #expect(text.runs.contains { $0.link != nil && $0.underlineStyle != nil })
    }

    @Test("裸の URL にも下線が引かれる")
    func bareURLIsUnderlined() {
        guard case .paragraph(let text) = blocks("見て https://example.com").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(text.runs.contains { $0.link != nil && $0.underlineStyle != nil })
    }

    @Test("リンクでない文字列には下線を引かない")
    func plainTextIsNotUnderlined() {
        guard case .paragraph(let text) = blocks("ただの本文です").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(text.runs.allSatisfy { $0.underlineStyle == nil })
    }

    @Test("裸の URL もリンクになる")
    func bareURL() {
        guard case .paragraph(let text) = blocks("見て https://example.com").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(text.runs.contains { $0.link != nil })
    }

    @Test("メールアドレスもリンクになる")
    func bareEmail() {
        guard case .paragraph(let text) = blocks("連絡は user@example.com まで").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(text.runs.contains { $0.link?.scheme == "mailto" })
    }

    @Test("スキームの無いドメインはリンクにしない（MarkdownCore と揃える）")
    func bareDomainIsNotLinked() {
        guard case .paragraph(let text) = blocks("ファイルは example.com にある").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(text.runs.allSatisfy { $0.link == nil })
    }

    @Test("インラインコードの中の URL はリンクにしない")
    func urlInsideCodeIsNotLinked() {
        guard case .paragraph(let text) = blocks("`https://example.com`").first?.content else {
            Issue.record("段落が取れていない")
            return
        }
        #expect(text.runs.allSatisfy { $0.link == nil })
    }

    @Test("空文字列ではブロックが生まれない")
    func emptySource() {
        #expect(blocks("").isEmpty)
    }
}
