#if canImport(AppKit)
import AppKit
import ImageIO
import Testing
import WebKit
@testable import NullnoteUI

@Suite("図の書き出し")
@MainActor
struct MermaidExportTests {

    // MARK: - ドラッグを選択に渡すか

    /// 200×100 の図。文字は (50, 40) から 100×20。
    let regions = DiagramTextRegions(
        size: CGSize(width: 200, height: 100),
        rects: [CGRect(x: 50, y: 40, width: 100, height: 20)]
    )

    @Test("文字の外から始めたドラッグは持ち出しに使う")
    func outsideTextExports() {
        #expect(regions.allowsExport(at: CGPoint(x: 10, y: 10), viewWidth: 600))
        #expect(regions.allowsExport(at: CGPoint(x: 190, y: 90), viewWidth: 600))
    }

    @Test("文字の上から始めたドラッグは選択に渡す")
    func onTextSelects() {
        #expect(!regions.allowsExport(at: CGPoint(x: 100, y: 50), viewWidth: 600))
        // 縁のわずかに外も、選ぶつもりだったとみなす。
        #expect(!regions.allowsExport(at: CGPoint(x: 49, y: 50), viewWidth: 600))
    }

    @Test("図の外（枠の余白）では持ち出さない")
    func outsideDiagram() {
        // 枠は図より広い。図の右の空白から引いても、図は付いてこない。
        #expect(!regions.allowsExport(at: CGPoint(x: 300, y: 50), viewWidth: 600))
        #expect(!regions.allowsExport(at: CGPoint(x: 10, y: 120), viewWidth: 600))
    }

    @Test("枠が狭くて図が縮んでいても、文字の場所を取り違えない")
    func scaledDown() {
        // 幅 100 の枠に収めると半分の大きさ。文字は (25, 20) から 50×10 に見えている。
        #expect(!regions.allowsExport(at: CGPoint(x: 50, y: 25), viewWidth: 100))
        // 縮める前の座標のまま比べると、ここを文字と取り違える。
        #expect(regions.allowsExport(at: CGPoint(x: 90, y: 45), viewWidth: 100))
        // 縮んだ図の外。
        #expect(!regions.allowsExport(at: CGPoint(x: 50, y: 60), viewWidth: 100))
    }

    @Test("頁から返ってきた値を読む")
    func parsesPageValue() {
        let value: [String: Any] = [
            "width": 200, "height": 100,
            "rects": [[50, 40, 100, 20], ["壊れた値"]],
        ]
        #expect(DiagramTextRegions(value) == regions)
        #expect(DiagramTextRegions(nil) == nil)
        #expect(DiagramTextRegions(["width": 0, "height": 0, "rects": []]) == nil)
    }

    // MARK: - ファイル

    @Test("名前には時刻を入れる")
    func fileName() {
        var components = DateComponents()
        components.year = 2026; components.month = 10; components.day = 2
        components.hour = 14; components.minute = 30; components.second = 5
        let date = Calendar.current.date(from: components)!
        let name = DiagramExportFormat.fileName(.png, at: date)
        #expect(name.hasSuffix(" 2026-10-02 14.30.05.png"))
        #expect(DiagramExportFormat.fileName(.svg, at: date).hasSuffix(".svg"))
    }

    @Test("ドラッグで落とした先に同じ名前があっても、潰さない")
    func writeDoesNotOverwrite() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let url = folder.appendingPathComponent("図.png")
        try DiagramDragSource.write(Data("1".utf8), near: url)
        try DiagramDragSource.write(Data("2".utf8), near: url)

        #expect(try Data(contentsOf: url) == Data("1".utf8))
        #expect(try Data(contentsOf: folder.appendingPathComponent("図 2.png")) == Data("2".utf8))
    }

    @Test("PNG に解像度を書き込む")
    func density() throws {
        let png = try #require(Self.solidPNG(width: 4, height: 4))
        let written = DiagramExporter.withDensity(png, scale: 2)
        let properties = try #require(Self.properties(of: written))
        #expect((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue == 144)
        #expect((properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue == 144)
        // 画素はそのまま。
        #expect((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue == 4)

        // 読めないものは、そのまま返す。
        #expect(DiagramExporter.withDensity(Data("x".utf8), scale: 2) == Data("x".utf8))
    }

    @Test("下地の色は、図が置かれている側の外観で解く")
    func resolvesBackground() {
        let color = PlatformColor.dynamic(light: .rgb(245, 245, 245), dark: .rgb(41, 50, 56))
        #expect(color.resolvedHex(in: NSAppearance(named: .aqua)!) == "#f5f5f5")
        #expect(color.resolvedHex(in: NSAppearance(named: .darkAqua)!) == "#293238")
    }

    // MARK: - 器

    @Test("書き出しの仕掛けが器に入っている")
    func hostHasExport() async throws {
        let host = try #require(MermaidCoordinator.hostURL)
        let html = try String(contentsOf: host, encoding: .utf8)
        // Swift 側から呼ぶ名前。変えるなら両方そろえること。
        #expect(html.contains("async function exportDiagram"))
        #expect(html.contains("textRegions: textRegions(el)"))
    }

    // MARK: - 実際に書き出す

    @Test("PNG は素の大きさの2倍で、下地が敷かれ、文字の場所も返ってくる")
    func exportsPNG() async throws {
        let (webView, drawn) = try await Self.render("flowchart LR\n  A[日本語] --> B[Hello]")
        defer { _ = webView }

        // 文字の場所が返ってくる。これが無いとドラッグが全部選択になる。
        let regions = try #require(DiagramTextRegions(drawn["textRegions"]))
        #expect(regions.rects.count >= 2)

        let png = try await DiagramExporter.data(.png, from: webView, background: "#102030")
        let properties = try #require(Self.properties(of: png))
        let width = try #require((properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue)
        let height = try #require((properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue)
        // 余白 16 を四方に足して、2倍。
        #expect(abs(width - (regions.size.width + 32) * 2) <= 1)
        #expect(abs(height - (regions.size.height + 32) * 2) <= 1)
        #expect((properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue == 144)

        // 角は下地の色。透けていない。
        let corner = try #require(Self.pixel(of: png, x: 1, y: 1))
        #expect(corner == [0x10, 0x20, 0x30, 0xff])
    }

    @Test("SVG には下地と文字が入っている")
    func exportsSVG() async throws {
        let (webView, _) = try await Self.render("flowchart LR\n  A[日本語] --> B[Hello]")
        defer { _ = webView }

        let data = try await DiagramExporter.data(.svg, from: webView, background: "#102030")
        let svg = try #require(String(data: data, encoding: .utf8))
        #expect(svg.hasPrefix("<?xml"))
        #expect(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
        #expect(svg.contains("fill=\"#102030\""))
        #expect(svg.contains("日本語"))
    }

    @Test("拡大窓で拡大していても、書き出す大きさは変わらない")
    func ignoresZoom() async throws {
        let (webView, _) = try await Self.render("flowchart LR\n  A --> B")
        defer { _ = webView }
        let before = try await DiagramExporter.data(.png, from: webView, background: "#ffffff")

        _ = try await webView.callAsyncJavaScript(
            "const s = document.querySelector('#box svg'); s.setAttribute('width', 3000); s.setAttribute('height', 3000);",
            arguments: [:], contentWorld: .page
        )
        let after = try await DiagramExporter.data(.png, from: webView, background: "#ffffff")
        let a = try #require(Self.properties(of: before)?[kCGImagePropertyPixelWidth] as? NSNumber)
        let b = try #require(Self.properties(of: after)?[kCGImagePropertyPixelWidth] as? NSNumber)
        #expect(a == b)
    }

    // MARK: - 枠の高さ

    @Test("枠の高さは、枠の幅に合わせて決め直す")
    func frameHeightFollowsWidth() {
        // 素の大きさ 563×450 の図（円グラフ）。
        let natural = CGSize(width: 563, height: 450)
        // 枠の方が広い：素の大きさのまま置かれる。
        #expect(DiagramFrame.height(for: natural, width: 800) == 450 + DiagramFrame.slack)
        // 枠の方が狭い：幅に合わせて縮む。
        #expect(DiagramFrame.height(for: natural, width: 400) == 320 + DiagramFrame.slack)
    }

    @Test("狭い幅で描いた図を広げても、高さの計算が頁と合う")
    func frameHeightMatchesPageAfterWidening() async throws {
        // **図の下が切れていた不具合の再現。** WebView は幅 400 で生まれ、
        // 図はその幅で描かれる。そのあと枠が広がると、図は素の大きさまで広がる。
        // 描いたときの高さ（約 320）で枠を固定していたため、下の 130 ほどが切れていた。
        let (webView, drawn) = try await Self.render(
            "pie title 内訳\n  \"本文\" : 62\n  \"コード\" : 23\n  \"図\" : 15", width: 400
        )
        let natural = CGSize(
            width: try #require((drawn["naturalWidth"] as? NSNumber)?.doubleValue),
            height: try #require((drawn["naturalHeight"] as? NSNumber)?.doubleValue)
        )
        try #require(natural.width > 400, "幅 400 より広い図で試すこと")
        let narrow = try #require((drawn["height"] as? NSNumber)?.doubleValue)

        for width in [800.0, 500.0, 300.0] {
            webView.setFrameSize(CGSize(width: width, height: 1000))
            let value = try await webView.callAsyncJavaScript(
                """
                for (let i = 0; i < 100 && window.innerWidth !== width; i++) {
                  await new Promise(r => setTimeout(r, 20));
                }
                if (window.innerWidth !== width) return -1;
                return document.querySelector('#box svg').getBoundingClientRect().height;
                """,
                arguments: ["width": width], contentWorld: .page
            )
            let shown = try #require((value as? NSNumber)?.doubleValue)
            try #require(shown >= 0, "頁の幅が \(width) にならない")
            let frame = DiagramFrame.height(for: natural, width: width)
            // 枠は図より 0〜2 だけ高い。図がはみ出さず、余白も残らない。
            #expect(frame >= shown && frame - shown <= DiagramFrame.slack + 1,
                    "幅 \(width): 枠 \(frame) / 図 \(shown)")
        }
        // 広げると、描いたときの高さより確かに高くなる（固定していたら切れていた）。
        #expect(DiagramFrame.height(for: natural, width: 800) > narrow + 100)
    }

    // MARK: - 道具

    /// 器を読み込んで図を描く。
    static func render(
        _ code: String, width: CGFloat = 600, theme: String = "default"
    ) async throws -> (WKWebView, [String: Any]) {
        let host = try #require(MermaidCoordinator.hostURL)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: width, height: 400))
        let loader = Loader()
        webView.navigationDelegate = loader
        await withCheckedContinuation { continuation in
            loader.finished = { continuation.resume() }
            webView.loadFileURL(host, allowingReadAccessTo: host.deletingLastPathComponent())
        }
        let value = try await webView.callAsyncJavaScript(
            "return await renderDiagram(code, theme);",
            arguments: ["code": code, "theme": theme], contentWorld: .page
        )
        let drawn = try #require(value as? [String: Any])
        try #require(drawn["ok"] as? Bool == true, "描けない: \(drawn)")
        return (webView, drawn)
    }

    final class Loader: NSObject, WKNavigationDelegate {
        var finished: (() -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            finished?()
            finished = nil
        }
    }

    static func properties(of data: Data) -> [CFString: Any]? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    }

    static func solidPNG(width: Int, height: Int) -> Data? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        return rep?.representation(using: .png, properties: [:])
    }

    /// 1画素を RGBA で読む。**色空間の変換を通さず、書かれた値をそのまま読む。**
    /// NSColor を経由すると、色空間の解釈しだいで値がずれる（実際にずれた）。
    static func pixel(of png: Data, x: Int, y: Int) -> [UInt8]? {
        guard let rep = NSBitmapImageRep(data: png), rep.samplesPerPixel == 4,
              rep.bitsPerSample == 8
        else { return nil }
        var samples = [Int](repeating: 0, count: 4)
        rep.getPixel(&samples, atX: x, y: y)
        return samples.map { UInt8($0) }
    }
}
#endif
