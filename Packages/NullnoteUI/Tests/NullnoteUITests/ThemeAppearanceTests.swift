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

    @Test("SwiftUI へ渡す値")
    func colorSchemeMapping() {
        #expect(MarkdownAppearance.system.colorScheme == nil)
        #expect(MarkdownAppearance.light.colorScheme == .light)
        #expect(MarkdownAppearance.dark.colorScheme == .dark)
    }

    @Test("保存と復元ができる（@AppStorage が使う経路）")
    func rawValueRoundTrip() {
        for appearance in MarkdownAppearance.allCases {
            #expect(MarkdownAppearance(rawValue: appearance.rawValue) == appearance)
        }
    }

    #if canImport(AppKit)
    @Test("AppKit へ渡す値。system は親から受け継ぐので nil")
    func platformAppearanceMapping() {
        #expect(MarkdownAppearance.system.platformAppearance == nil)
        #expect(MarkdownAppearance.light.platformAppearance?.name == .aqua)
        #expect(MarkdownAppearance.dark.platformAppearance?.name == .darkAqua)
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
