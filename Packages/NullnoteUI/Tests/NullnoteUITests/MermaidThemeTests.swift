#if canImport(AppKit)
import AppKit
import SwiftUI
import Testing
import WebKit
@testable import NullnoteUI

@Suite("図のテーマ")
@MainActor
struct MermaidThemeTests {

    @Test("既定はライトが neutral、ダークが dark")
    func defaults() {
        let themes = MermaidThemes()
        #expect(themes.theme(for: .light) == .neutral)
        #expect(themes.theme(for: .dark) == .dark)
    }

    @Test("外観に合わせて、選んだ方を使う")
    func followsAppearance() {
        let themes = MermaidThemes(light: .forest, dark: .base)
        #expect(themes.theme(for: .light) == .forest)
        #expect(themes.theme(for: .dark) == .base)
        // 外観が決まっていないときはライトとして扱う（前の作りと同じ）。
        #expect(themes.theme(for: nil) == .forest)
    }

    @Test("設定に残る綴りは mermaid のテーマ名そのもの")
    func rawValuesAreMermaidNames() {
        // 変えると、保存済みの設定が読めなくなり、mermaid にも通じなくなる。
        #expect(MermaidTheme.allCases.map(\.rawValue) == ["default", "neutral", "forest", "base", "dark"])
    }

    @Test("どのテーマも mermaid に通じ、色が変わる")
    func everyThemeRenders() async throws {
        var fills: [String: String] = [:]
        for theme in MermaidTheme.allCases {
            let (webView, _) = try await MermaidExportTests.render(
                "flowchart LR\n  A[箱] --> B[箱]", theme: theme.rawValue
            )
            let value = try await webView.callAsyncJavaScript(
                "return getComputedStyle(document.querySelector('#box svg .node rect')).fill;",
                arguments: [:], contentWorld: .page
            )
            fills[theme.rawValue] = try #require(value as? String)
        }
        // 名前を綴り違えると、mermaid は黙って default で描く。全部の色が違えば、全部通じている。
        #expect(Set(fills.values).count == MermaidTheme.allCases.count, "\(fills)")
    }
}
#endif
