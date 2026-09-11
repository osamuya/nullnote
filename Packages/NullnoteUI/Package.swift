// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NullnoteUI",
    // 画面の文字列をこのパッケージの中に持つため、既定の言語を宣言する。
    // これが無いと localized resources を置けない。
    // **このパッケージの文字列は Bundle.module から引く。**
    // 使う側で bundle: .module を渡し忘れると Bundle.main を見にいき、
    // 訳が見つからず日本語のまま出る（エラーにはならない）。docs/12-make-multilingual.md
    defaultLocalization: "ja",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "NullnoteUI", targets: ["NullnoteUI"]),
    ],
    dependencies: [
        .package(path: "../MarkdownCore"),
        // プレビューの描画にのみ使う。エディタのハイライト経路には持ち込まない。
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.8.0"),
    ],
    targets: [
        .target(
            name: "NullnoteUI",
            dependencies: [
                "MarkdownCore",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            // 画面の文字列。Bundle.module に入るので、使う側で bundle: .module が要る。
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(name: "NullnoteUITests", dependencies: ["NullnoteUI"]),
    ]
)
