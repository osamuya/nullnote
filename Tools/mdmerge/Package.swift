// swift-tools-version: 6.2
import PackageDescription

// 開発用の道具。**アプリには入らない。**
// アプリと同じ合流の規則を使うため、`MarkdownCore` を借りる。
let package = Package(
    name: "mdmerge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../Packages/MarkdownCore"),
    ],
    targets: [
        .executableTarget(
            name: "mdmerge",
            dependencies: [.product(name: "MarkdownCore", package: "MarkdownCore")]
        ),
        .testTarget(name: "mdmergeTests", dependencies: ["mdmerge"]),
    ]
)
