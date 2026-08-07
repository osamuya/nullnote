import Testing
@testable import NullnoteUI

@Suite("フッターの表示")
struct StatusBarTests {

    @Test(
        "行数の数え方が行番号と一致する",
        arguments: [
            "",
            "1行だけ",
            "末尾が改行\n",
            "2行\nある",
            "空行を挟む\n\n最後",
            "\n",
            "\n\n\n",
        ]
    )
    func lineCountMatchesLineIndex(source: String) {
        // フッターと行番号で数え方がずれると、見比べたときに食い違う。
        // 末尾が改行のときの「その後ろの空行」を数えるかどうかが分かれ目。
        #expect(DocumentSize.lineCount(of: source) == LineIndex(source).lineCount)
    }

    @Test("改行の直後に文字が無くても1行として数える")
    func trailingNewlineCountsAsLine() {
        #expect(DocumentSize.lineCount(of: "本文") == 1)
        #expect(DocumentSize.lineCount(of: "本文\n") == 2)
        #expect(DocumentSize.lineCount(of: "本文\n\n") == 3)
    }

    @Test("大きさは UTF-8 のバイト数で数える")
    func sizeUsesUTF8Bytes() {
        // 日本語は1文字3バイト。文字数で数えていると気づけない。
        #expect("あ".utf8.count == 3)
        #expect(DocumentSize.byteLabel(of: "あ") != DocumentSize.byteLabel(of: "aaaaaaaaaa"))
        #expect(DocumentSize.byteLabel(of: "").isEmpty == false)
    }

    @Test("テーマの名前は設定画面と同じ言葉を使う")
    func appearanceLabels() {
        #expect(MarkdownAppearance.system.label == "システム")
        #expect(MarkdownAppearance.light.label == "ライト")
        #expect(MarkdownAppearance.dark.label == "ダーク")
    }
}
