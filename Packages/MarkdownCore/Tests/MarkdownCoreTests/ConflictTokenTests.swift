import Testing
@testable import MarkdownCore

@Suite("合流の印を記法として拾う")
struct ConflictTokenTests {

    /// 印つきの本文。`ThreeWayMerge` が実際に出す形。
    private let source = """
        <<<<<<< Internal updates
        こちらの版
        =======
        外の版
        >>>>>>> External updates
        """

    @Test("5つの部分に分かれる")
    func parts() {
        let kinds = MarkdownTokenizer.snapshot(source)
            .compactMap { if case .conflict(let part) = $0.kind { part } else { nil } }
        #expect(kinds == [.ourMarker, .ourBody, .separator, .theirBody, .theirMarker])
    }

    @Test("中身が複数行でも、それぞれ塗り分ける")
    func multiLineBodies() {
        let source = """
            <<<<<<< Internal updates
            1行目
            2行目
            =======
            外の1行目
            >>>>>>> External updates
            """
        let kinds = MarkdownTokenizer.snapshot(source)
            .compactMap { if case .conflict(let part) = $0.kind { part } else { nil } }
        #expect(kinds == [.ourMarker, .ourBody, .ourBody, .separator, .theirBody, .theirMarker])
    }

    /// `=======` は CommonMark では setext 見出しにもなる。
    /// **印の中にいるときだけ**仕切りとして扱う。
    @Test("印の外の ======= は、いままでどおり見出し")
    func separatorOutsideConflict() {
        let kinds = MarkdownTokenizer.snapshot("見出し\n=======")
            .compactMap { if case .conflict(let part) = $0.kind { part } else { nil } }
        #expect(kinds.isEmpty)
    }

    @Test("印を抜けたら、ふつうの記法に戻る")
    func backToNormal() {
        let source = """
            <<<<<<< Internal updates
            a
            =======
            b
            >>>>>>> External updates
            # 見出し
            """
        let tokens = MarkdownTokenizer.snapshot(source)
        #expect(tokens.contains { $0.kind == .heading(level: 1) })
    }

    /// コードブロックの中でぶつかることもある。**そこでも塗れないと読めない。**
    @Test("コードブロックの中でも印として拾う")
    func insideCodeBlock() {
        let source = """
            ```swift
            <<<<<<< Internal updates
            let a = 1
            =======
            let a = 2
            >>>>>>> External updates
            ```
            """
        let kinds = MarkdownTokenizer.snapshot(source)
            .compactMap { if case .conflict(let part) = $0.kind { part } else { nil } }
        #expect(kinds.contains(.ourMarker))
        #expect(kinds.contains(.theirMarker))
    }

    /// 綴りの完全一致で見る。**大文字小文字の違いも別物。**
    @Test("似ているだけの行は拾わない")
    func lookalikes() {
        for line in [
            "<<<<<<<", "<<<<<<< 別の言葉", ">>>>>>> 外部の更新です",
            "<<<<<<< internal updates", ">>>>>>> External updates です",
        ] {
            let kinds = MarkdownTokenizer.snapshot(line)
                .compactMap { if case .conflict(let part) = $0.kind { part } else { nil } }
            #expect(kinds.isEmpty, "「\(line)」を印として拾ってしまった")
        }
    }

    /// **書くのは英語だけ。** 画面の言語では変えない（D-64）。
    @Test("書く印は英語で固定")
    func writesEnglishMarkers() {
        #expect(ThreeWayMerge.ourMarker == "<<<<<<< Internal updates")
        #expect(ThreeWayMerge.theirMarker == ">>>>>>> External updates")
    }

    /// 1.1 までは日本語の印を書いていた。
    /// **片付けないまま上げた書類でも、印として読む**（D-64）。
    @Test("1.1 までの日本語の印も拾う")
    func legacyJapaneseMarkers() {
        let source = """
            <<<<<<< 自分の更新
            こちらの版
            =======
            外の版
            >>>>>>> 外部の更新
            """
        let kinds = MarkdownTokenizer.snapshot(source)
            .compactMap { if case .conflict(let part) = $0.kind { part } else { nil } }
        #expect(kinds == [.ourMarker, .ourBody, .separator, .theirBody, .theirMarker])
        #expect(ConflictScanner.regions(in: source).count == 1)
    }
}
