import Testing
@testable import MarkdownCore

@Suite("選んだところを記法で囲む")
struct InlineWrapTests {

    // MARK: - 囲む

    @Test("選んだ文字を記法で挟む")
    func wrap() {
        #expect(InlineWrap.wrap("Nullnote", with: .emphasis).text == "*Nullnote*")
        #expect(InlineWrap.wrap("Nullnote", with: .strong).text == "**Nullnote**")
        #expect(InlineWrap.wrap("Nullnote", with: .code).text == "`Nullnote`")
        #expect(InlineWrap.wrap("Nullnote", with: .strikethrough).text == "~Nullnote~")
        #expect(InlineWrap.wrap("Nullnote", with: .bracket).text == "[Nullnote]")
    }

    @Test("囲んだ中身は選ばれたまま残る（重ねがけできる）")
    func selectionSurvives() {
        let result = InlineWrap.wrap("Nullnote", with: .emphasis)
        #expect(result.caretOffset == 1)              // `*` の次
        #expect(result.selectionLength == 8)          // 「Nullnote」
    }

    @Test("日本語も文字数どおりに数える")
    func japanese() {
        let result = InlineWrap.wrap("見出し", with: .strong)
        #expect(result.text == "**見出し**")
        #expect(result.caretOffset == 2)
        #expect(result.selectionLength == 3)
    }

    // MARK: - リンク

    @Test("リンクはカーソルを行き先の位置に置く")
    func link() {
        let result = InlineWrap.wrap("Nullnote", with: .link)
        #expect(result.text == "[Nullnote]()")
        // `[Nullnote](` までで 11 文字。その直後。
        #expect(result.caretOffset == 11)
        #expect(result.selectionLength == 0)
    }

    @Test("選択が無くてもリンクは作れる")
    func emptyLink() {
        let result = InlineWrap.wrap("", with: .link)
        #expect(result.text == "[]()")
        #expect(result.caretOffset == 3)
    }

    // MARK: - 選択が無いとき

    @Test("選択が無ければ、記法だけ置いてあいだにカーソル")
    func empty() {
        let result = InlineWrap.wrap("", with: .strong)
        #expect(result.text == "****")
        #expect(result.caretOffset == 2)
        #expect(result.selectionLength == 0)
    }

    // MARK: - 記号キーの割り当て

    @Test("囲む記号は4つだけ")
    func typedCharacters() {
        #expect(InlineWrap.style(forTypedCharacter: "*") == .emphasis)
        #expect(InlineWrap.style(forTypedCharacter: "`") == .code)
        #expect(InlineWrap.style(forTypedCharacter: "~") == .strikethrough)
        #expect(InlineWrap.style(forTypedCharacter: "[") == .bracket)
    }

    @Test("それ以外の記号は、ふつうに文字が入る")
    func otherCharacters() {
        // `_` は snake_case、`(` `\"` はふつうに打ちたい場面が多い。
        #expect(InlineWrap.style(forTypedCharacter: "_") == nil)
        #expect(InlineWrap.style(forTypedCharacter: "(") == nil)
        #expect(InlineWrap.style(forTypedCharacter: "\"") == nil)
        #expect(InlineWrap.style(forTypedCharacter: "a") == nil)
    }
}
