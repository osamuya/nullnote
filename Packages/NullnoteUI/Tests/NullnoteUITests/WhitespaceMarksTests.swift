import Foundation
import Testing
@testable import NullnoteUI

/// 編集画面で印を描く空白の位置（D-80）。
@Suite("空白の印の位置")
struct WhitespaceMarksTests {

    private func marks(_ text: String) -> [String] {
        let string = text as NSString
        return WhitespaceMarks.find(in: string, range: NSRange(location: 0, length: string.length))
            .map { "\($0.location):\($0.mark == .space ? "␣" : "□")" }
    }

    @Test("半角スペースには、行のどこにあっても ␣ を付ける")
    func spaces() {
        #expect(marks("a b") == ["1:␣"])
        #expect(marks("一行目  \n二行目") == ["3:␣", "4:␣"])
    }

    @Test("全角スペースには □ を付ける")
    func ideographicSpaces() {
        #expect(marks("　段落の頭") == ["0:□"])
        #expect(marks("文　 ") == ["1:□", "2:␣"])
    }

    @Test("タブや改行には付けない")
    func otherWhitespace() {
        #expect(marks("a\tb\nc\r\n") == [])
    }

    @Test("渡した範囲だけを見る")
    func limitedRange() {
        #expect(WhitespaceMarks.find(in: "a b c" as NSString, range: NSRange(location: 2, length: 3))
            .map(\.location) == [3])
    }
}
