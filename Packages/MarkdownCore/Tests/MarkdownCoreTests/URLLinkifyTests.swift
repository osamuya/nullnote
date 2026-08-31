import Testing
@testable import MarkdownCore

@Suite("URL をリンクにする")
struct URLLinkifyTests {

    /// 行末にカーソルがある状態で、区切りを打った瞬間の判断。
    private func atEnd(_ line: String) -> URLLinkify.Replacement? {
        URLLinkify.replacement(line: line, caretUTF16Offset: line.utf16.count)
    }

    // MARK: - 変える

    @Test("打ち終えた URL を [URL](URL) にする")
    func linkify() {
        let result = atEnd("https://sabanote.com/apps/")
        #expect(result?.text == "[https://sabanote.com/apps/](https://sabanote.com/apps/)")
        #expect(result?.range == 0..<26)
    }

    @Test("文の途中の URL でも、その部分だけを変える")
    func inSentence() {
        let line = "詳しくは https://sabanote.com/"
        let result = atEnd(line)
        #expect(result?.text == "[https://sabanote.com/](https://sabanote.com/)")
        // 「詳しくは 」のあと（UTF-16 で5文字）から。
        #expect(result?.range.lowerBound == 5)
    }

    @Test("http:// も変える")
    func http() {
        #expect(atEnd("http://example.com")?.text
                == "[http://example.com](http://example.com)")
    }

    // MARK: - 変えない

    @Test("www. で始まるものは変えない")
    func wwwIsLeftAlone() {
        // `](www.…)` はブラウザで相対パスとして読まれ、リンク先が壊れる。
        #expect(atEnd("www.example.com") == nil)
    }

    @Test("ドットの無いホスト名も変える")
    func dotlessHosts() {
        // 手元の開発、Docker Compose のサービス名、社内の単一ラベル。
        #expect(atEnd("http://localhost:6080/apps/")?.text
                == "[http://localhost:6080/apps/](http://localhost:6080/apps/)")
        #expect(atEnd("http://api:8000/")?.text == "[http://api:8000/](http://api:8000/)")
        #expect(atEnd("http://wiki/")?.text == "[http://wiki/](http://wiki/)")
    }

    /// `[http://[::1]:8080/](…)` はラベルの中に角括弧が入り、
    /// CommonMark がリンクとして読めない。エスケープすれば通せるが、
    /// 見た目が汚れる割に出番が無いので外している。
    @Test("IPv6 のリテラルは変えない（記法が壊れるため）")
    func ipv6IsLeftAlone() {
        #expect(atEnd("http://[::1]:8080/") == nil)
    }

    @Test("IP アドレスも変える")
    func ipv4() {
        #expect(atEnd("http://192.168.1.10:8080/")?.text
                == "[http://192.168.1.10:8080/](http://192.168.1.10:8080/)")
    }

    @Test("短いドメインも変える（文字数では判定しない）")
    func shortDomain() {
        #expect(atEnd("http://sum.com/")?.text == "[http://sum.com/](http://sum.com/)")
    }

    @Test("ホストが無いものは変えない")
    func noHost() {
        #expect(atEnd("https://") == nil)
        #expect(atEnd("http://?query") == nil)
        #expect(atEnd("http:///path") == nil)
    }

    @Test("ホストの形をしていないものは変えない")
    func malformedHost() {
        // ハイフンやドットで始まる・終わるもの。
        #expect(atEnd("http://-bad/") == nil)
        #expect(atEnd("http://bad./") == nil)
        // ホストに使えない文字。
        #expect(atEnd("http://a_b/") == nil)
    }

    @Test("すでにリンクの中にあるものは変えない")
    func alreadyLinked() {
        #expect(atEnd("[見出し](https://sabanote.com/") == nil)
        #expect(atEnd("<https://sabanote.com/") == nil)
    }

    /// 先に `[]()` を書いてから中に URL を入れると、二重に囲まれていた（実測）。
    @Test("閉じていない括弧の中では作らない")
    func insideParentheses() {
        #expect(!URLLinkify.allowsLinkify(line: "[](", caretUTF16Offset: 3))
        #expect(!URLLinkify.allowsLinkify(
            line: "[](http://192.168.1.10:8080/", caretUTF16Offset: 28))
        #expect(!URLLinkify.allowsLinkify(line: "(詳しくは ", caretUTF16Offset: 6))
        #expect(!URLLinkify.allowsLinkify(line: "<", caretUTF16Offset: 1))
    }

    @Test("括弧が閉じていれば作ってよい")
    func afterClosedParentheses() {
        #expect(URLLinkify.allowsLinkify(line: "[見出し](https://a.com/) ", caretUTF16Offset: 22))
        #expect(URLLinkify.allowsLinkify(line: "ふつうの文章 ", caretUTF16Offset: 7))
        #expect(URLLinkify.allowsLinkify(line: "", caretUTF16Offset: 0))
    }

    @Test("URL でない語は変えない")
    func notAURL() {
        #expect(atEnd("ふつうの文章") == nil)
        #expect(atEnd("") == nil)
    }

    @Test("記法の一部を含むものは触らない")
    func containsMarkup() {
        #expect(atEnd("https://example.com/a)b") == nil)
    }

    // MARK: - 貼り付け

    @Test("URL だけを貼ったらリンクにする")
    func paste() {
        #expect(URLLinkify.linkify(pasted: "https://sabanote.com/apps/")
                == "[https://sabanote.com/apps/](https://sabanote.com/apps/)")
    }

    @Test("前後に空白が付いていたら触らない")
    func pasteWithWhitespace() {
        #expect(URLLinkify.linkify(pasted: " https://sabanote.com/ ") == nil)
        #expect(URLLinkify.linkify(pasted: "https://sabanote.com/\n") == nil)
    }

    @Test("文章ごと貼ったときは触らない")
    func pasteSentence() {
        #expect(URLLinkify.linkify(pasted: "詳しくは https://sabanote.com/ を見てください") == nil)
    }
}
