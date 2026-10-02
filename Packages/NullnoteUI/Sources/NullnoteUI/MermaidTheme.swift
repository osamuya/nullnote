import SwiftUI

/// mermaid の図の配色。mermaid が持っているテーマをそのまま選ぶ（D-70）。
///
/// **`rawValue` は mermaid に渡す名前そのもの。** 設定にもこの綴りで残るので変えないこと。
public enum MermaidTheme: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case neutral
    case forest
    case base
    case dark

    public var id: String { rawValue }

    /// Nullnote がライトのときの既定。灰色で、本文の邪魔をしない。
    public static let lightDefault: MermaidTheme = .neutral
    /// Nullnote がダークのときの既定。mermaid のテーマでダーク向けはこれだけ。
    public static let darkDefault: MermaidTheme = .dark

    /// 設定画面に出す名前。**mermaid の名前を残す。** 図の中に
    /// `%%{init: {'theme': 'forest'}}%%` と書く人が、同じ名前で探せるように。
    public var label: LocalizedStringResource {
        switch self {
        case .default: LocalizedStringResource("default（紫）", bundle: .module)
        case .neutral: LocalizedStringResource("neutral（灰色）", bundle: .module)
        case .forest: LocalizedStringResource("forest（緑）", bundle: .module)
        case .base: LocalizedStringResource("base（クリーム）", bundle: .module)
        case .dark: LocalizedStringResource("dark（黒）", bundle: .module)
        }
    }
}

/// ライトのときとダークのときに使う、図のテーマの組。
public struct MermaidThemes: Equatable, Sendable {
    public var light: MermaidTheme
    public var dark: MermaidTheme

    public init(light: MermaidTheme = .lightDefault, dark: MermaidTheme = .darkDefault) {
        self.light = light
        self.dark = dark
    }

    /// いまの外観で使うテーマ。外観が決まっていない（`nil`）ときはライトとして扱う。
    /// 前の作り（`== .dark ? "dark" : "default"`）と同じ扱い。
    public func theme(for scheme: ColorScheme?) -> MermaidTheme {
        scheme == .dark ? dark : light
    }
}

extension EnvironmentValues {
    /// 図に使うテーマ。プレビューの外から渡す。
    @Entry var mermaidThemes = MermaidThemes()
}

extension View {
    /// プレビューの図に使うテーマを決める。
    public func mermaidThemes(_ themes: MermaidThemes) -> some View {
        environment(\.mermaidThemes, themes)
    }
}
