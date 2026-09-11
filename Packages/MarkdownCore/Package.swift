// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MarkdownCore",
    // 画面に出る文字列を持つため、既定の言語を宣言する。
    // 詳細は docs/12-make-multilingual.md。
    defaultLocalization: "ja",
    // macOS アプリが先行するが、iOS 展開時にそのまま載せ替えられるよう
    // 最初から両プラットフォームを宣言しておく。
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "MarkdownCore", targets: ["MarkdownCore"]),
    ],
    targets: [
        // AppKit / UIKit / SwiftUI には依存しない。依存を足す場合は必ず Foundation まで。
        .target(name: "MarkdownCore"),
        .testTarget(name: "MarkdownCoreTests", dependencies: ["MarkdownCore"]),
    ]
)
