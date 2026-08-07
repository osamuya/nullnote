import SwiftUI

#if canImport(AppKit)
import AppKit

/// OS の外観（ライト／ダーク）を見張る。
///
/// `.system` を具体的な配色に解決する以上、**OS 側が変わったことを自分で知る必要がある。**
/// 解決せずに `preferredColorScheme(nil)` を渡すと、ライトなど明示指定から戻したときに
/// SwiftUI が解決する色だけ古いまま残る（決定記録の B-12）。
@MainActor
final class SystemAppearance: ObservableObject {

    static let shared = SystemAppearance()

    @Published private(set) var colorScheme: ColorScheme

    private var observation: NSKeyValueObservation?

    private init() {
        colorScheme = Self.current
        // `NSApp.appearance` は SwiftUI が触らない（ウインドウ側だけ書き換える）ので、
        // ここが変わるのは OS の設定が変わったときだけ。
        observation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self, self.colorScheme != Self.current else { return }
                self.colorScheme = Self.current
            }
        }
    }

    static var current: ColorScheme {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance(named: .aqua)!
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}
#endif

extension MarkdownAppearance {

    /// SwiftUI へ渡す配色。**`.system` でも nil を返さない。**
    ///
    /// nil は「好みなし」であって「システムに合わせ直せ」ではない。
    /// ライト → システムと戻したとき、SwiftUI 側の配色が
    /// ライトのまま残る（決定記録の B-12）。
    @MainActor
    var resolvedColorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        #if canImport(AppKit)
        case .system: SystemAppearance.current
        #else
        // UIKit ではこの問題は起きない。OS 追従は SwiftUI に任せる。
        case .system: nil
        #endif
        }
    }
}

extension View {

    /// 設定に合わせて配色を決める。OS の設定が変わったら付いていく。
    ///
    /// `preferredColorScheme` を直に呼ばないこと。`.system` のときの扱いを
    /// 1か所に閉じ込めておかないと、また B-12 を踏む。
    public func markdownColorScheme(_ appearance: MarkdownAppearance) -> some View {
        modifier(MarkdownColorScheme(appearance: appearance))
    }
}

private struct MarkdownColorScheme: ViewModifier {

    let appearance: MarkdownAppearance

    #if canImport(AppKit)
    /// OS の外観が変わったときに body を作り直させるためだけに持つ。
    @ObservedObject private var system = SystemAppearance.shared
    #endif

    func body(content: Content) -> some View {
        content.preferredColorScheme(appearance.resolvedColorScheme)
    }
}
