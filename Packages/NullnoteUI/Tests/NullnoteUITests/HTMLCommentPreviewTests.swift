import Foundation
import Testing
@testable import NullnoteUI

/// HTML コメントはプレビューに出さない。
///
/// 下書きのメモや、いったん外した節を文書に残しておくための書き方なので、
/// 見えては意味が無い。**コードとして書いたものは消さない。**
@Suite("HTML コメントはプレビューに出ない")
struct HTMLCommentPreviewTests {

    func blocks(_ source: String) -> [PreviewBlock] {
        PreviewBuilder.build(source, theme: .standard())
    }

    /// プレビューに出る文字を全部つないだもの。
    func visibleText(_ source: String) -> String {
        blocks(source).map { block in
            switch block.content {
            case .paragraph(let text): String(text.characters)
            case .heading(_, let text): String(text.characters)
            case .codeBlock(let code, _): code
            default: ""
            }
        }.joined(separator: "\n")
    }

    @Test("行頭のコメントは消える")
    func blockComment() {
        let text = visibleText("本文A\n\n<!-- メモ -->\n\n本文B\n")
        #expect(text.contains("本文A"))
        #expect(text.contains("本文B"))
        #expect(!text.contains("メモ"))
    }

    @Test("複数行のコメントは中身ごと消える")
    func multilineComment() {
        let text = visibleText("本文A\n\n<!--\n## 外した節\n外した本文\n-->\n\n本文B\n")
        #expect(text.contains("本文A"))
        #expect(text.contains("本文B"))
        #expect(!text.contains("外した節"))
        #expect(!text.contains("外した本文"))
    }

    @Test("本文の途中のコメントだけが消える")
    func inlineComment() {
        let text = visibleText("本文の<!-- メモ -->途中です。\n")
        #expect(text.contains("本文の"))
        #expect(text.contains("途中です。"))
        #expect(!text.contains("メモ"))
    }

    @Test("コメントだけになった段落は置かない")
    func emptiedParagraphIsDropped() {
        // 空の段落を置くと、そこだけ行間が空いて見える。
        let source = "本文A\n\n<!-- メモ -->\n\n本文B\n"
        #expect(blocks(source).count == 2)
    }

    @Test("コードブロックの中のコメントは消さない")
    func insideCodeBlockSurvives() {
        // 書いてあるとおりに見せるための場所。ここまで消したら壊れている。
        #expect(visibleText("```html\n<!-- メモ -->\n```\n").contains("<!-- メモ -->"))
    }

    @Test("インラインコードの中のコメントは消さない")
    func insideCodeSpanSurvives() {
        #expect(visibleText("`<!-- メモ -->` と書きます。\n").contains("<!-- メモ -->"))
    }

    @Test("コメント以外の HTML は今までどおり見せる")
    func otherHTMLIsUnchanged() {
        #expect(visibleText("<div>ふつうの HTML</div>\n").contains("<div>ふつうの HTML</div>"))
    }

    @Test("コメントの中の見出しは目次に出ない")
    func outlineSkipsComments() {
        let outline = DocumentOutline.build(from: "# 生きている見出し\n\n<!--\n## 外した節\n-->\n")
        #expect(outline.count == 1)
        #expect(outline.first?.title == "生きている見出し")
        #expect(outline.first?.children == nil, "コメントの中の見出しが目次に残っている")
    }
}
