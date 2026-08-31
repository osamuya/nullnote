import Testing
@testable import MarkdownCore

@Suite("リストの深さを変える")
struct IndentChangeTests {

    // MARK: - 深くする

    @Test("リストの行なら、選んだ単位を足す")
    func deepen() {
        #expect(IndentChange.deepen(line: "1. foo", unit: "    ") == "    ")
        #expect(IndentChange.deepen(line: "- foo", unit: "\t") == "\t")
        #expect(IndentChange.deepen(line: "  - foo", unit: "  ") == "  ")
    }

    @Test("リストでない行は深くしない")
    func deepenOnlyLists() {
        #expect(IndentChange.deepen(line: "ふつうの段落", unit: "    ") == nil)
        #expect(IndentChange.deepen(line: "# 見出し", unit: "    ") == nil)
        #expect(IndentChange.deepen(line: "", unit: "    ") == nil)
    }

    @Test("引用は深さを変えない")
    func quoteIsNotIndented() {
        #expect(IndentChange.deepen(line: "> 引用", unit: "    ") == nil)
        #expect(IndentChange.shallow(line: "  > 引用") == nil)
    }

    // MARK: - 浅くする

    @Test("タブで書かれていればタブを1つ外す")
    func shallowTab() {
        #expect(IndentChange.shallow(line: "\t1. foo") == 1)
        #expect(IndentChange.shallow(line: "\t\t- foo") == 1)
    }

    @Test("スペースは4桁の区切りまで戻る")
    func shallowSpaces() {
        #expect(IndentChange.shallow(line: "    1. foo") == 4)
        #expect(IndentChange.shallow(line: "        - foo") == 4)
    }

    @Test("2つ刻みの文書でも、あるぶんだけ外す")
    func shallowTwoSpaces() {
        #expect(IndentChange.shallow(line: "  - foo") == 2)
        #expect(IndentChange.shallow(line: "   - foo") == 3)
    }

    @Test("インデットが無ければ、外すものが無い")
    func shallowNothing() {
        #expect(IndentChange.shallow(line: "1. foo") == nil)
        #expect(IndentChange.shallow(line: "- foo") == nil)
    }

    @Test("リストでない行は浅くしない")
    func shallowOnlyLists() {
        #expect(IndentChange.shallow(line: "    ふつうの段落") == nil)
    }
}
