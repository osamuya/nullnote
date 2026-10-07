import Foundation
import ImageIO
import UniformTypeIdentifiers
import WebKit

// mermaid の図を画像として持ち出す（#M0044）。
//
// - プレビューの図は、**文字の外から**ドラッグすると PNG を持ち出せる。
//   文字の上から始めたドラッグは、今までどおり選択になる（拡大窓の移動と同じ使い分け。D-65）。
// - 拡大窓には保存のボタンを置く。拡大窓のドラッグは移動と選択に使っているので、
//   持ち出しには使わない。
//
// **画像はいつも素の大きさの2倍で作る。** 画面の拡大率には合わせない。
// **下地を敷く。** プレビューで図の後ろに見えている色。透かすと、ダークの図を
// 白い資料に貼ったときに白い文字が消える。
// 作るのは `host.html` の `exportDiagram`。判断の記録は D-69。

/// 書き出す形式。
enum DiagramExportFormat: String, Sendable {
    case png
    case svg

    var contentType: UTType {
        switch self {
        case .png: .png
        case .svg: .svg
        }
    }

    /// 保存するときの名前。`図 2026-10-02 14.30.12.png` の形。
    /// **時刻を入れる。** 同じ場所へ続けて落としても、前の画像を潰さない。
    static func fileName(_ format: DiagramExportFormat, at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let base = String(localized: "図", bundle: .module)
        return "\(base) \(formatter.string(from: date)).\(format.rawValue)"
    }
}

/// 書き出しに失敗したとき。
struct DiagramExportError: LocalizedError {
    let reason: String

    var errorDescription: String? {
        String(localized: "図を書き出せませんでした", bundle: .module)
    }

    var failureReason: String? { reason }
}

/// 図の中で文字が占めている場所。ドラッグを選択に渡すか、持ち出しに使うかを決める。
///
/// 座標は**図の素の大きさ**を基準にしている（頁の `textRegions`）。
/// プレビューでは図が枠の幅に合わせて縮むので、押した場所を素の大きさへ戻してから比べる。
struct DiagramTextRegions: Equatable, Sendable {
    /// 図の素の大きさ。
    var size: CGSize
    /// 文字のある場所。
    var rects: [CGRect]

    /// 文字の縁をわずかに広げる。ぎりぎりの所から始めたドラッグは、
    /// 選ぶつもりだったことが多い。
    static let margin: CGFloat = 2

    /// 頁から返ってきた値を読む。形が崩れていれば `nil`。
    init?(_ value: Any?) {
        guard let dictionary = value as? [String: Any],
              let width = (dictionary["width"] as? NSNumber)?.doubleValue,
              let height = (dictionary["height"] as? NSNumber)?.doubleValue,
              width > 0, height > 0,
              let list = dictionary["rects"] as? [Any]
        else { return nil }
        self.size = CGSize(width: width, height: height)
        self.rects = list.compactMap { item in
            guard let numbers = item as? [NSNumber], numbers.count == 4 else { return nil }
            return CGRect(
                x: numbers[0].doubleValue, y: numbers[1].doubleValue,
                width: numbers[2].doubleValue, height: numbers[3].doubleValue
            )
        }
    }

    init(size: CGSize, rects: [CGRect]) {
        self.size = size
        self.rects = rects
    }

    /// その場所から始めたドラッグで、図を持ち出してよいか。
    ///
    /// - Parameters:
    ///   - point: 押した場所。**左上が原点**の、枠の中の座標。
    ///   - viewWidth: 枠の幅。図はこれより広ければ縮めて置かれている（`max-width: 100%`）。
    /// - Returns: 図の上で、文字の上ではないとき `true`。図の外（枠の余白）は `false`。
    func allowsExport(at point: CGPoint, viewWidth: CGFloat) -> Bool {
        guard size.width > 0, viewWidth > 0 else { return false }
        let scale = min(viewWidth, size.width) / size.width
        let natural = CGPoint(x: point.x / scale, y: point.y / scale)
        guard CGRect(origin: .zero, size: size).contains(natural) else { return false }
        let margin = Self.margin / scale
        return !rects.contains { $0.insetBy(dx: -margin, dy: -margin).contains(natural) }
    }
}

/// 頁に図を書き出させる。
@MainActor
enum DiagramExporter {

    /// 図を書き出す。
    ///
    /// - Parameter background: 下地の色。`#rrggbb`。
    static func data(
        _ format: DiagramExportFormat, from webView: WKWebView, background: String
    ) async throws -> Data {
        let value: Any?
        do {
            value = try await webView.callAsyncJavaScript(
                "return await exportDiagram(format, background);",
                arguments: ["format": format.rawValue, "background": background],
                contentWorld: .page
            )
        } catch {
            throw DiagramExportError(reason: error.localizedDescription)
        }
        guard let dictionary = value as? [String: Any] else {
            throw DiagramExportError(reason: "no result")
        }
        guard dictionary["ok"] as? Bool == true else {
            throw DiagramExportError(reason: dictionary["reason"] as? String ?? "?")
        }
        switch format {
        case .svg:
            guard let text = dictionary["svg"] as? String else {
                throw DiagramExportError(reason: "no svg")
            }
            return Data(text.utf8)
        case .png:
            guard let base64 = dictionary["png"] as? String,
                  let png = Data(base64Encoded: base64)
            else { throw DiagramExportError(reason: "no png") }
            let scale = (dictionary["scale"] as? NSNumber)?.doubleValue ?? 1
            return withDensity(png, scale: scale)
        }
    }

    /// PNG に解像度を書き込む。
    ///
    /// canvas の PNG は 72dpi として出てくる。2倍で作った画像をそのまま貼ると、
    /// Pages や Keynote では倍の大きさで置かれる。`144dpi` と書いておけば、
    /// 素の大きさで置かれ、そのぶん細かく見える。書き込めなければ元のまま返す。
    nonisolated static func withDensity(_ png: Data, scale: Double) -> Data {
        guard scale > 0,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              CGImageSourceGetCount(source) == 1
        else { return png }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { return png }
        let dpi = 72 * scale
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return png }
        return output as Data
    }
}

// MARK: - 色

extension PlatformColor {
    /// 書き出す図の下地に使う色。`#rrggbb`。
    ///
    /// **透明度は捨てる。** 下地は塗りつぶすためのもの。
    /// 動的な色は、呼ぶ側で外観を決めてから読むこと（`resolvedHex(in:)`）。
    @MainActor var hexString: String {
        #if canImport(AppKit)
        let resolved = usingColorSpace(.sRGB) ?? .white
        let red = resolved.redComponent, green = resolved.greenComponent, blue = resolved.blueComponent
        #else
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif
        func byte(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(red), byte(green), byte(blue))
    }
}

#if canImport(AppKit)
import AppKit

extension PlatformColor {
    /// その外観で見えている色を `#rrggbb` で返す。
    ///
    /// **図が置かれている側の外観で解く。** テーマの外観をアプリと別にしていると、
    /// いま画面全体が使っている側とは限らない。
    @MainActor func resolvedHex(in appearance: NSAppearance) -> String {
        var hex = "#ffffff"
        appearance.performAsCurrentDrawingAppearance { hex = self.hexString }
        return hex
    }
}

// MARK: - 保存

@MainActor
enum DiagramSaving {

    /// 保存の窓を出して、選ばれた場所へ書く。
    ///
    /// 書き出しは**場所が決まってから**行う。取り消されたときに無駄に作らない。
    /// サンドボックスでも、保存の窓で選ばれた場所には書ける
    /// （`files.user-selected.read-write`）。
    static func save(
        _ format: DiagramExportFormat, from webView: WKWebView, background: PlatformColor
    ) {
        guard let window = webView.window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = DiagramExportFormat.fileName(format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try await DiagramExporter.data(
                        format, from: webView,
                        background: background.resolvedHex(in: webView.effectiveAppearance)
                    )
                    try data.write(to: url, options: .atomic)
                    Trace.log("Mermaid: \(format.rawValue) を保存 \(data.count) bytes")
                } catch {
                    Trace.log("Mermaid: 保存できない \(error)")
                    NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
                }
            }
        }
    }
}

// MARK: - プレビューからのドラッグ

/// プレビューの図から PNG を持ち出す。
///
/// **押した瞬間に作り始め、できていれば画像そのものも渡す。**
/// 間に合わなかったときはファイルの約束（file promise）だけを渡し、
/// 落とされた時点で作って書く。Finder・メール・Pages などは約束で受け取れる。
/// 画像そのものを渡さないと受け取れない相手もいるので、できていれば両方載せる。
@MainActor
final class DiagramDragSource: NSObject, NSDraggingSource, NSFilePromiseProviderDelegate {

    private weak var webView: WKWebView?
    /// 下地の色。テーマが変わったら差し替える。
    var background: PlatformColor {
        didSet { if background != oldValue { prepared = nil } }
    }

    /// 作り終えた PNG。図が変われば WebView ごと作り直されるので、ここは捨てなくてよい。
    private var prepared: Data?
    private var preparing: Task<Data, Error>?

    init(webView: WKWebView, background: PlatformColor) {
        self.webView = webView
        self.background = background
    }

    /// PNG を作り始める。押した瞬間に呼ぶ。
    func prepare() {
        guard prepared == nil, preparing == nil else { return }
        preparing = Task { @MainActor in
            defer { preparing = nil }
            let data = try await makePNG()
            prepared = data
            return data
        }
    }

    private func makePNG() async throws -> Data {
        guard let webView else { throw DiagramExportError(reason: "no view") }
        return try await DiagramExporter.data(
            .png, from: webView,
            background: background.resolvedHex(in: webView.effectiveAppearance)
        )
    }

    private func png() async throws -> Data {
        if let prepared { return prepared }
        if let preparing { return try await preparing.value }
        let data = try await makePNG()
        prepared = data
        return data
    }

    /// ドラッグを始める。
    func beginDrag(with event: NSEvent, from view: NSView) {
        let provider = DiagramPromiseProvider(fileType: UTType.png.identifier, delegate: self)
        provider.png = prepared

        let item = NSDraggingItem(pasteboardWriter: provider)
        let image = dragImage()
        let point = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            CGRect(
                x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
                width: image.size.width, height: image.size.height
            ),
            contents: image
        )
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    /// 指に付いてくる絵。**できていれば図そのもの**を小さくして見せる。
    private func dragImage() -> NSImage {
        let limit: CGFloat = 200
        if let prepared, let image = NSImage(data: prepared), image.size.width > 0 {
            let ratio = min(1, limit / max(image.size.width, image.size.height))
            image.size = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
            return image
        }
        let icon = NSWorkspace.shared.icon(for: .png)
        icon.size = CGSize(width: 64, height: 64)
        return icon
    }

    // MARK: NSDraggingSource

    nonisolated func draggingSession(
        _ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // アプリの中（本文）へ落とすことは考えない。外へ渡すときだけ。
        context == .outsideApplication ? .copy : []
    }

    // MARK: NSFilePromiseProviderDelegate

    nonisolated func filePromiseProvider(
        _ provider: NSFilePromiseProvider, fileNameForType fileType: String
    ) -> String {
        DiagramExportFormat.fileName(.png)
    }

    nonisolated func filePromiseProvider(
        _ provider: NSFilePromiseProvider, writePromiseTo url: URL,
        completionHandler: @escaping (Error?) -> Void
    ) {
        // AppKit は、どのスレッドから呼び返してもよいとしている。
        nonisolated(unsafe) let completionHandler = completionHandler
        Task { @MainActor in
            do {
                let data = try await self.png()
                try Self.write(data, near: url)
                completionHandler(nil)
            } catch {
                Trace.log("Mermaid: ドラッグで渡せない \(error)")
                completionHandler(error)
            }
        }
    }

    /// 書く。**同じ名前があれば潰さず、番号を付ける。**
    nonisolated static func write(_ data: Data, near url: URL) throws {
        let folder = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = url
        var number = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(stem) \(number)").appendingPathExtension(ext)
            number += 1
        }
        try data.write(to: candidate, options: .withoutOverwriting)
    }
}

/// ファイルの約束に、できていれば PNG そのものも添える。
final class DiagramPromiseProvider: NSFilePromiseProvider {

    var png: Data?

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        var types = super.writableTypes(for: pasteboard)
        if png != nil { types.append(.png) }
        return types
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        if type == .png { return png }
        return super.pasteboardPropertyList(forType: type)
    }
}
#endif
