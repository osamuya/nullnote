import SwiftUI
import Testing
@testable import NullnoteUI

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

@Suite("テーマの外観")
struct ThemeAppearanceTests {

    @Test("既定はシステムに従う")
    func defaultsToSystem() {
        #expect(MarkdownTheme.standard().appearance == .system)
    }

    @Test("設定した外観がテーマに載る", arguments: MarkdownAppearance.allCases)
    func appearanceIsCarried(appearance: MarkdownAppearance) {
        #expect(MarkdownTheme.standard(appearance: appearance).appearance == appearance)
    }

    /// 回帰テスト（決定記録 B-12）。
    ///
    /// `.system` で nil を返すと、ライトなど明示指定から戻したときに
    /// SwiftUI が解決する色（プレビューの背景やフッター）が古いまま残る。
    @Test("SwiftUI へ渡す値も、必ず具体的な配色になる")
    @MainActor
    func colorSchemeMapping() {
        #expect(MarkdownAppearance.light.resolvedColorScheme == .light)
        #expect(MarkdownAppearance.dark.resolvedColorScheme == .dark)

        let resolved = MarkdownAppearance.system.resolvedColorScheme
        #expect(resolved != nil, "システムのときに nil を返している")
        #expect(resolved == SystemAppearance.current)
    }

    @Test("保存と復元ができる（@AppStorage が使う経路）")
    func rawValueRoundTrip() {
        for appearance in MarkdownAppearance.allCases {
            #expect(MarkdownAppearance(rawValue: appearance.rawValue) == appearance)
        }
    }

    #if canImport(AppKit)
    @Test("AppKit へ渡す値は必ず具体的な外観になる")
    @MainActor
    func platformAppearanceMapping() {
        #expect(MarkdownAppearance.light.platformAppearance.name == .aqua)
        #expect(MarkdownAppearance.dark.platformAppearance.name == .darkAqua)

        // `.system` でも nil（＝親から継承）を返してはいけない。
        // 明示指定から継承へ戻したとき、AppKit が実効外観を下位へ伝えず、
        // 「ライト → システム」でライトのまま残る（決定記録の B-8）。
        let resolved = MarkdownAppearance.system.platformAppearance.name
        #expect(resolved == .aqua || resolved == .darkAqua)
    }

    @Test("外観を指定すると、同じ動的な色が別の値に解決する")
    func dynamicColorsResolveDifferently() throws {
        let theme = MarkdownTheme.standard()
        let light = try #require(NSAppearance(named: .aqua))
        let dark = try #require(NSAppearance(named: .darkAqua))

        var lightBackground: NSColor?
        var darkBackground: NSColor?
        light.performAsCurrentDrawingAppearance {
            lightBackground = theme.background.usingColorSpace(.deviceRGB)
        }
        dark.performAsCurrentDrawingAppearance {
            darkBackground = theme.background.usingColorSpace(.deviceRGB)
        }

        let lightBrightness = try #require(lightBackground?.brightnessComponent)
        let darkBrightness = try #require(darkBackground?.brightnessComponent)
        #expect(lightBrightness > 0.9, "ライトの背景が明るくない")
        #expect(darkBrightness < 0.3, "ダークの背景が暗くない")
    }
    #endif
}
