#if canImport(AppKit)
import AppKit
import Foundation
import MarkdownCore
import Testing
@testable import NullnoteUI

/// 一時的な実測用。計測が済んだら消す。
@Suite("一時計測")
@MainActor
struct TempBenchmark {

    static let path = ProcessInfo.processInfo.environment["BENCH_FILE"] ?? ""

    func measure(_ label: String, times: Int = 10, _ body: () -> Void) {
        body()
        let start = Date()
        for _ in 0..<times { body() }
        let each = Date().timeIntervalSince(start) / Double(times) * 1000
        print(String(format: "%-46@ %8.2f ms", label as NSString, each))
    }

    @Test("打鍵1回ぶんの経路を測る")
    func bench() throws {
        let source = try String(contentsOfFile: Self.path, encoding: .utf8)
        print("\n文字数 \(source.count) / 行数 \(source.split(separator: "\n", omittingEmptySubsequences: false).count)")
        let theme = MarkdownTheme.standard()

        print("\n── 打鍵のたびに走る（エディタ） ──")
        let tokenizer = MarkdownTokenizer()
        measure("MarkdownTokenizer.tokenizeLines") { _ = tokenizer.tokenizeLines(source) }
        let storage = NSTextStorage(string: source)
        let highlighter = MarkdownHighlighter(theme: theme)
        measure("MarkdownHighlighter.apply") { highlighter.apply(to: storage, text: source) }
        measure("LineIndex の作り直し") { _ = LineIndex(source) }

        print("\n── 打鍵のたびに走る（フッター） ──")
        measure("DocumentSize.lineCount") { _ = DocumentSize.lineCount(of: source) }
        measure("DocumentSize.byteLabel") { _ = DocumentSize.byteLabel(of: source) }

        print("\n── 入力が止まってから走る ──")
        measure("DocumentOutline.build（目次 200ms 後）", times: 5) { _ = DocumentOutline.build(from: source) }
        measure("PreviewBuilder.build（プレビュー 150ms 後）", times: 5) { _ = PreviewBuilder.build(source, theme: theme) }

        print("\n── プレビューの中身 ──")
        let blocks = PreviewBuilder.build(source, theme: theme)
        var tables = 0, cells = 0
        for block in blocks {
            if case .table(let table) = block.content {
                tables += 1
                cells += table.header.count + table.rows.reduce(0) { $0 + $1.count }
            }
        }
        print("ブロック \(blocks.count) / 表 \(tables) / 表のマス \(cells)")

        // マス1枚は NSTextView 1枚。属性の組み立てと測定がマスの数だけ走る。
        var oneCell: AttributedString?
        for block in blocks {
            if case .table(let table) = block.content, let cell = table.rows.first?.first {
                oneCell = cell; break
            }
        }
        if let cell = oneCell {
            measure("PreviewAttributes.make（マス1枚）", times: 500) {
                _ = PreviewAttributes.make(from: cell, theme: theme, baseFont: theme.bodyFont, baseColor: theme.text)
            }
        }
        print("")
    }
}
#endif
