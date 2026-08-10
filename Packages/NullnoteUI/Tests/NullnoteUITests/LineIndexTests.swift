import Foundation
import Testing
@testable import NullnoteUI

@Suite("行の索引")
struct LineIndexTests {

    // MARK: - 行の範囲

    @Test("行の範囲に改行は含めない")
    func rangeExcludesNewline() {
        let index = LineIndex("あ\nいう\nえ")
        #expect(index.utf16Range(ofLine: 1) == NSRange(location: 0, length: 1))
        #expect(index.utf16Range(ofLine: 2) == NSRange(location: 2, length: 2))
        #expect(index.utf16Range(ofLine: 3) == NSRange(location: 5, length: 1))
    }

    @Test("空行の範囲は長さ 0")
    func emptyLine() {
        let index = LineIndex("あ\n\nい")
        #expect(index.utf16Range(ofLine: 2) == NSRange(location: 2, length: 0))
    }

    @Test("末尾が改行なら、その後ろの空行も引ける")
    func trailingNewline() {
        let index = LineIndex("あ\n")
        #expect(index.lineCount == 2)
        #expect(index.utf16Range(ofLine: 2) == NSRange(location: 2, length: 0))
    }

    @Test("CRLF でも改行を含めない")
    func carriageReturnLineFeed() {
        // Swift は "\r\n" を1文字として扱うが、UTF-16 では2。
        // 数え違えると行の範囲が1つずれる。
        let index = LineIndex("あ\r\nい")
        #expect(index.lineCount == 2)
        #expect(index.utf16Range(ofLine: 1) == NSRange(location: 0, length: 1))
        #expect(index.utf16Range(ofLine: 2) == NSRange(location: 3, length: 1))
    }

    @Test("絵文字を含む行でも UTF-16 で数える")
    func surrogatePairs() {
        let source = "🙂あ\nい"
        let index = LineIndex(source)
        let line = index.utf16Range(ofLine: 1)
        #expect(line == NSRange(location: 0, length: 3))
        #expect((source as NSString).substring(with: line) == "🙂あ")
    }

    @Test("範囲外の行番号は、いちばん近い行に丸める")
    func clampsOutOfRange() {
        let index = LineIndex("あ\nい")
        #expect(index.utf16Range(ofLine: 0) == index.utf16Range(ofLine: 1))
        #expect(index.utf16Range(ofLine: 99) == index.utf16Range(ofLine: 2))
    }

    @Test("空の本文でも落ちない")
    func emptySource() {
        let index = LineIndex("")
        #expect(index.lineCount == 1)
        #expect(index.utf16Range(ofLine: 1) == NSRange(location: 0, length: 0))
    }

    // MARK: - 行の先頭と行番号

    @Test("行の先頭は行の範囲の始まりと一致する")
    func startMatchesRange() {
        let index = LineIndex("あ\nいう\n\nえ\n")
        for line in 1...index.lineCount {
            #expect(index.utf16Offset(ofLine: line) == index.utf16Range(ofLine: line).location)
        }
    }

    @Test("行の中のどこを指しても同じ行番号になる")
    func lineNumberWithinRange() {
        let source = "あ\nいうえ\nお"
        let index = LineIndex(source)
        let line = index.utf16Range(ofLine: 2)
        for offset in line.location..<(line.location + line.length) {
            #expect(index.line(atUTF16Offset: offset) == 2)
        }
    }
}
