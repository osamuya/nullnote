// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NullnoteUI",
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
            ]
        ),
        .testTarget(name: "NullnoteUITests", dependencies: ["NullnoteUI"]),
    ]
)
