import Testing
@testable import MarkdownCore

/// 合流の印の探し方。
///
/// 印は Markdown の記法ではない。解釈させる前に切り分けるための下ごしらえで、
/// **どこからどこまでが印か**をここで決める（D-60）。
@Suite("合流の印を探す")
struct ConflictScannerTests {

    private let ours = ThreeWayMerge.ourMarker
    private let separator = ThreeWayMerge.separator
    private let theirs = ThreeWayMerge.theirMarker

    @Test("印で割られたところを見つける")
    func findsRegion() {
        let source = """
        前置き
        \(ours)
        こちらの直し
        \(separator)
        外の直し
        \(theirs)
        あとがき
        """
        let found = ConflictScanner.regions(in: source)
        #expect(found.count == 1)
        #expect(found.first?.ourMarkerLine == 1)
        #expect(found.first?.separatorLine == 3)
        #expect(found.first?.theirMarkerLine == 5)
        #expect(found.first?.ourBody == 2..<3)
        #expect(found.first?.theirBody == 4..<5)
    }

    @Test("印がひとつも無ければ空")
    func findsNothing() {
        #expect(ConflictScanner.regions(in: "ふつうの本文\nもう1行").isEmpty)
    }

    @Test("いくつあっても順に見つける")
    func findsSeveral() {
        let source = """
        \(ours)
        A
        \(separator)
        B
        \(theirs)
        あいだ
        \(ours)
        C
        \(separator)
        D
        \(theirs)
        """
        #expect(ConflictScanner.regions(in: source).count == 2)
    }

    @Test("閉じていない印は、印として扱わない")
    func ignoresUnclosed() {
        // 書きかけの `<<<<<<<` を打っただけで本文が消えたように見えるのを避ける。
        let source = """
        \(ours)
        こちらの直し
        \(separator)
        外の直し
        """
        #expect(ConflictScanner.regions(in: source).isEmpty)
    }

    @Test("仕切りが無いまま閉じても、印として扱わない")
    func ignoresMissingSeparator() {
        #expect(ConflictScanner.regions(in: "\(ours)\nA\n\(theirs)").isEmpty)
    }

    @Test("片側が空でも見つける")
    func findsEmptySide() {
        // 外だけが書き足した競合では、自分の側が空になる。
        let found = ConflictScanner.regions(in: "\(ours)\n\(separator)\n外の直し\n\(theirs)")
        #expect(found.first?.ourBody.isEmpty == true)
        #expect(found.first?.theirBody == 2..<3)
    }

    @Test("綴りが違う行は印として扱わない")
    func ignoresOtherSpellings() {
        // git の一般形（`<<<<<<< branch-name`）は拾わない。
        // 編集画面の色分けと同じ見方にしてある。
        let source = """
        <<<<<<< HEAD
        A
        \(separator)
        B
        >>>>>>> feature
        """
        #expect(ConflictScanner.regions(in: source).isEmpty)
    }

    @Test("前後に空白があっても印として読む")
    func trimsWhitespace() {
        let source = "  \(ours)  \n A \n \(separator) \n B \n  \(theirs) "
        #expect(ConflictScanner.regions(in: source).count == 1)
    }
}
