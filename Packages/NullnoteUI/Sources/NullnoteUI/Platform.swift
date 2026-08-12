#if canImport(AppKit)
import AppKit

public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformTextView = NSTextView
/// 文字列の記憶域が「何を書き換えたか」。AppKit と UIKit で型の名前が違う。
typealias PlatformTextStorageEditActions = NSTextStorageEditActions
#elseif canImport(UIKit)
import UIKit

public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformTextView = UITextView
/// 文字列の記憶域が「何を書き換えたか」。AppKit と UIKit で型の名前が違う。
typealias PlatformTextStorageEditActions = NSTextStorage.EditActions
#endif

import CoreGraphics
import SwiftUI

// このファイルが AppKit と UIKit の差を吸収する唯一の場所。
// 新しい差分が出たら、ここに寄せてから使うこと。

extension MarkdownAppearance {

    #if canImport(AppKit)
    /// AppKit のビューへ設定する値。**必ず具体的な外観を返す。**
    ///
    /// `.system` のときに `nil`（＝親から継承）を設定してはいけない。
    /// 明示指定から継承へ戻したとき、AppKit が実効外観を下位のビューへ伝えず、
    /// 「ライト → システム」でライトのまま残る（`docs/02-decision-log.md` の B-8）。
    /// システムの現在の外観へ自分で解決する。
    @MainActor var platformAppearance: NSAppearance {
        switch self {
        case .system: NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!
        case .light: NSAppearance(named: .aqua)!
        case .dark: NSAppearance(named: .darkAqua)!
        }
    }
    #elseif canImport(UIKit)
    /// UIKit のビューへ設定する値。
    var platformInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
    #endif
}

extension Color {
    /// テーマの色を SwiftUI 側で使う。外観への追従はそのまま引き継がれる。
    public init(platform color: PlatformColor) {
        #if canImport(AppKit)
        self.init(nsColor: color)
        #else
        self.init(uiColor: color)
        #endif
    }
}

extension PlatformColor {

    /// 外観に追従する色。ライト・ダークで別の値を返す。
    static func dynamic(light: PlatformColor, dark: PlatformColor) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
        #else
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        }
        #endif
    }

    /// 0〜255 の値から色を作る。値は **sRGB** として解釈する。
    ///
    /// `NSColor(red:green:blue:alpha:)` は calibrated RGB として解釈するため、
    /// 指定した 16 進の値と実際に描かれる色がわずかにずれる
    /// （`#0000FF` が `#0000F5` になる、など）。
    /// デザインで決めた値をそのまま出すために、色空間を明示する。
    static func rgb(_ red: Double, _ green: Double, _ blue: Double) -> PlatformColor {
        #if canImport(AppKit)
        NSColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
        #else
        UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: 1)
        #endif
    }
}

extension PlatformFont {

    /// 太字・斜体を「足す」。既にある特性は落とさない。
    ///
    /// トークンは外側から内側の順に適用されるため、`**太字の中の *斜体* **` では
    /// 斜体を足す時点で太字が付いている。上書きすると外側の指定が消える。
    func addingTraits(bold: Bool = false, italic: Bool = false) -> PlatformFont {
        guard bold || italic else { return self }

        #if canImport(AppKit)
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }
        let descriptor = fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
        #else
        var traits = fontDescriptor.symbolicTraits
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard let descriptor = fontDescriptor.withSymbolicTraits(traits) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
        #endif
    }

    static func editorBody(size: CGFloat) -> PlatformFont {
        #if canImport(AppKit)
        NSFont.systemFont(ofSize: size)
        #else
        UIFont.systemFont(ofSize: size)
        #endif
    }

    static func editorMonospaced(size: CGFloat) -> PlatformFont {
        #if canImport(AppKit)
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #else
        UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        #endif
    }
}
