import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import NullnoteUI

/// 同じ名前のまま差し替えられた画像を、読み直せるか（#M0047）。
@Suite("画像の読み込みと覚え方")
struct ImageLoaderTests {

    /// 一辺が `side` の PNG を作る。大きさで絵を見分ける。
    private static func png(side: Int) throws -> Data {
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())

        let data = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageLoaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// 読んだ結果の一辺。読めなかったら nil。
    private static func loadedSide(
        _ loader: ImageLoader, _ source: String, document: URL
    ) async -> CGFloat? {
        guard case .loaded(let image) = await loader.load(source, relativeTo: document) else {
            return nil
        }
        return image.size.width
    }

    @Test("その場で上書きされた画像を読み直す")
    func overwrittenInPlace() async throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = folder.appendingPathComponent("本文.md")
        let image = folder.appendingPathComponent("bar.png")
        let loader = ImageLoader()

        try Self.png(side: 10).write(to: image)
        #expect(await Self.loadedSide(loader, "bar.png", document: document) == 10)

        let handle = try FileHandle(forWritingTo: image)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Self.png(side: 20))
        try handle.close()
        #expect(await Self.loadedSide(loader, "bar.png", document: document) == 20)
    }

    @Test("置き換えで保存された画像を読み直す")
    func replacedAtomically() async throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = folder.appendingPathComponent("本文.md")
        let image = folder.appendingPathComponent("bar.png")
        let loader = ImageLoader()

        try Self.png(side: 10).write(to: image)
        #expect(await Self.loadedSide(loader, "bar.png", document: document) == 10)

        // 多くのソフトは別名で書いてから被せる（`rename(2)`）。
        try Self.png(side: 30).write(to: image, options: .atomic)
        #expect(await Self.loadedSide(loader, "bar.png", document: document) == 30)
    }

    @Test("変わっていなければ覚えている絵を返す")
    func unchangedIsCached() async throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = folder.appendingPathComponent("本文.md")
        try Self.png(side: 10).write(to: folder.appendingPathComponent("bar.png"))
        let loader = ImageLoader()

        guard case .loaded(let first) = await loader.load("bar.png", relativeTo: document),
              case .loaded(let second) = await loader.load("bar.png", relativeTo: document)
        else {
            Issue.record("読めなかった")
            return
        }
        // 同じ実体が返る。読み直していない。
        #expect(first === second)
    }

    @Test("消された画像は「見つかりません」になる。古い絵を出し続けない")
    func removedIsNotFound() async throws {
        let folder = try Self.makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let document = folder.appendingPathComponent("本文.md")
        let image = folder.appendingPathComponent("bar.png")
        let loader = ImageLoader()

        try Self.png(side: 10).write(to: image)
        #expect(await Self.loadedSide(loader, "bar.png", document: document) == 10)

        try FileManager.default.removeItem(at: image)
        #expect(await loader.load("bar.png", relativeTo: document) == .failed(.notFound))
    }
}
