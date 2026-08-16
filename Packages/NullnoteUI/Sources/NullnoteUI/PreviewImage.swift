import SwiftUI

/// 段落ぶんの画像。置き方に合わせて並べる。
///
/// サムネイルは折り返しながら横に並べ、押すと元の大きさで開く。
/// それ以外は縦に積む。
struct PreviewImagesView: View {

    let images: [PreviewImageRef]
    let theme: MarkdownTheme
    let documentURL: URL?

    /// 拡大して見ている画像の位置。**文書全体での位置**。押されたときだけ入る。
    @State private var zoomedIndex: Int?
    /// 文書ぜんぶの画像。段落をまたいで送るために使う。
    @Environment(\.previewImageList) private var allImages

    /// サムネイル1枚の大きさ。正方形に切って並べる。
    private static let thumbnailSide: CGFloat = 120

    var body: some View {
        content
            #if !canImport(AppKit)
            // iOS には窓が無いので、こちらはシートのまま。
            .sheet(isPresented: isZooming) {
                ZoomedImageView(
                    images: allImages.isEmpty ? images : allImages,
                    index: Binding(get: { zoomedIndex ?? 0 }, set: { zoomedIndex = $0 }),
                    theme: theme, documentURL: documentURL, onClose: { zoomedIndex = nil }
                )
            }
            #endif
    }

    private var isZooming: Binding<Bool> {
        Binding(get: { zoomedIndex != nil }, set: { if !$0 { zoomedIndex = nil } })
    }

    /// 拡大して見せる。
    ///
    /// **シートではなく独立した窓で開く。** シートは利用者が大きさを変えられず、
    /// 大きな絵を見るのに向かない。窓なら広げられるし、全画面にもできる。
    private func zoom(at position: Int) {
        let list = allImages.isEmpty ? images : allImages
        #if canImport(AppKit)
        ImageZoomWindow.shared.show(
            images: list, startAt: position, theme: theme, documentURL: documentURL
        )
        #else
        zoomedIndex = position
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if images.allSatisfy({ $0.layout == .thumbnail }) {
            // 折り返しながら横に並べる。数が増えても縦に伸びるだけ。
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Self.thumbnailSide), spacing: 8, alignment: .leading)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(Array(images.enumerated()), id: \.element.id) { position, image in
                    PreviewImageView(
                        source: image.source, alt: image.alt, layout: image.layout,
                        theme: theme, documentURL: documentURL,
                        side: Self.thumbnailSide
                    ) { zoom(at: documentPosition(of: image, fallback: position)) }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: theme.fontSize * 0.6) {
                ForEach(Array(images.enumerated()), id: \.element.id) { position, image in
                    PreviewImageView(
                        source: image.source, alt: image.alt, layout: image.layout,
                        theme: theme, documentURL: documentURL, side: Self.thumbnailSide
                    ) { zoom(at: documentPosition(of: image, fallback: position)) }
                }
            }
        }
    }

    /// その画像が、文書全体で何番目か。
    private func documentPosition(of image: PreviewImageRef, fallback: Int) -> Int {
        allImages.firstIndex { $0.id == image.id } ?? fallback
    }
}

/// 押されたサムネイルを大きく開く。
///
/// **絵の全体が見えることを優先する。** 元の大きさで出すとはみ出してスクロールになり、
/// 何が写っているのか分からない。窓に収まるところまで縮めて出す。
struct ZoomedImageView: View {

    let images: [PreviewImageRef]
    @Binding var index: Int
    let theme: MarkdownTheme
    let documentURL: URL?
    /// 閉じる操作。窓のときは窓を閉じ、シートのときはシートを畳む。
    let onClose: () -> Void

    private var current: PreviewImageRef { images[min(max(index, 0), images.count - 1)] }

    var body: some View {
        VStack(spacing: 0) {
            PreviewImageView(
                source: current.source, alt: current.alt, layout: .fitted,
                theme: theme, documentURL: documentURL, side: 0, onTap: nil
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(16)

            Divider()
            controls
        }
        .frame(minWidth: 320, minHeight: 240)
        .background(Color(platform: theme.background))
        .markdownColorScheme(theme.appearance)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            if images.count > 1 {
                step(systemImage: "chevron.left", help: "前の画像へ（←）", key: .leftArrow) { move(by: -1) }
                    .disabled(index <= 0)
                Text("\(index + 1) / \(images.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(platform: theme.quote))
                step(systemImage: "chevron.right", help: "次の画像へ（→）", key: .rightArrow) { move(by: 1) }
                    .disabled(index >= images.count - 1)
            }

            Text(current.alt)
                .font(.system(size: theme.fontSize * 0.9))
                .foregroundStyle(Color(platform: theme.quote))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("閉じる") { onClose() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func step(
        systemImage: String, help: String, key: KeyEquivalent, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(platform: theme.text))
        .keyboardShortcut(key, modifiers: [])
        .help(help)
        .accessibilityLabel(help)
    }

    /// 端で止まる。**回らない。**
    /// 一覧を眺める操作なので、いつのまにか先頭へ戻っている方が分かりにくい。
    private func move(by offset: Int) {
        guard !images.isEmpty else { return }
        index = min(max(index + offset, 0), images.count - 1)
    }
}

/// プレビューに置く画像1枚。
///
/// 読めるまで、読めなかったときは**代替テキストを見せる**。
/// 何も出ないと、書いたはずの画像が消えたのか、そもそも書けていないのか分からない。
struct PreviewImageView: View {

    let source: String
    let alt: String
    let layout: PreviewImageLayout
    let theme: MarkdownTheme
    /// 相対パスの基準にする文書。新規で未保存なら nil。
    let documentURL: URL?
    /// サムネイルの一辺。
    let side: CGFloat
    /// 押されたときに呼ぶ。サムネイルのときだけ入る。
    var onTap: (() -> Void)?

    @State private var state: LoadState = .loading
    @Environment(\.imageAccessRequester) private var accessRequester

    enum LoadState: Equatable {
        case loading
        case loaded(PlatformImage)
        /// 読めなかった理由。画面に出して、次の手が分かるようにする。
        case failed(ImageLoader.Failure)
    }

    var body: some View {
        content
            .task(id: ImageLoadKey(source: source, document: documentURL)) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loaded(let image):
            switch layout {
            case .thumbnail:
                // 正方形に切って並べる。縦横比の違う写真が混ざっても列が乱れない。
                Image(platform: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .onTapGesture { onTap?() }
                    .help(alt.isEmpty ? "押すと大きく表示します" : "\(alt) — 押すと大きく表示します")
                    .accessibilityLabel(alt.isEmpty ? "画像" : alt)

            case .center:
                // **幅いっぱいに広げる。** 元より小さい絵は引き伸ばされる。
                // 指定した人が「全幅で見せたい」と言っている以上、そちらに従う。
                Image(platform: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(alt.isEmpty ? "画像" : alt)

            case .fitted:
                // 与えられた場所に収まるだけ広げる。はみ出させない。
                Image(platform: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(alt.isEmpty ? "画像" : alt)

            case .normal:
                Image(platform: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // 元の大きさより引き伸ばさない。粗くなるだけで得が無い。
                    .frame(maxWidth: image.size.width)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(alt.isEmpty ? "画像" : alt)
            }

        case .loading:
            placeholder(alt.isEmpty ? "画像を読み込み中…" : alt)

        case .failed(let failure):
            HStack(spacing: 10) {
                placeholder("\(alt.isEmpty ? "画像" : alt) — \(failure.reason)")
                // 許可さえあれば読めるものだけ、頼む口を出す。
                // 「見つかりません」に許可のボタンを出しても、押しても直らない。
                if failure == .noPermission, accessRequester != nil {
                    Button("許可する…") { Task { await requestAccess() } }
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        // **アプリ全体の色（黄色）を使わない。**
                        // ここは本文の中に置かれる小さなボタンで、
                        // 明るい黄色だとライトの地に溶けて読めない。
                        // 記法の灰色に寄せて、本文より一段引いた見た目にする。
                        .tint(Color(platform: theme.quote))
                        .help("この画像があるフォルダの閲覧を許可します")
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "photo")
            Text(text)
        }
        .font(.system(size: theme.fontSize * 0.9))
        .foregroundStyle(Color(platform: theme.quote))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(platform: theme.codeBackground))
        )
    }

    private func load() async {
        state = .loading
        state = await ImageLoader.shared.load(source, relativeTo: documentURL)
    }

    /// フォルダの閲覧を頼み、許されたら読み直す。
    private func requestAccess() async {
        guard let accessRequester,
              case .local(let url) = ImageSourceResolver.resolve(source, relativeTo: documentURL)
        else { return }

        let granted = await accessRequester.request(url.deletingLastPathComponent())
        guard granted else { return }
        await load()
    }

    /// 読み直しの合図。場所か基準が変われば読み直す。
    private struct ImageLoadKey: Hashable {
        let source: String
        let document: URL?
    }
}

/// 画像を読む。
///
/// 一度読んだものは覚えておく。プレビューは打鍵のたびに組み直されるので、
/// 覚えていないと同じ画像を何度も読み直すことになる。
actor ImageLoader {

    static let shared = ImageLoader()

    /// 読めなかった理由。**「無い」と「読めない」は分けて見せる。**
    /// 前者は書き間違い、後者は許可の問題で、利用者がやることが違う。
    enum Failure: Equatable {
        case notFound
        case noPermission
        case unreadable
        case badSource

        var reason: String {
            switch self {
            case .notFound: "見つかりません"
            case .noPermission: "読む許可がありません"
            case .unreadable: "読み込めません"
            case .badSource: "場所が分かりません"
            }
        }
    }

    private var cache: [URL: PlatformImage] = [:]

    func load(_ source: String, relativeTo document: URL?) async -> PreviewImageView.LoadState {
        guard let resolved = ImageSourceResolver.resolve(source, relativeTo: document) else {
            return .failed(.badSource)
        }

        switch resolved {
        case .local(let url):
            if let cached = cache[url] { return .loaded(cached) }
            return loadLocal(url)

        case .remote(let url):
            if let cached = cache[url] { return .loaded(cached) }
            return await loadRemote(url)
        }
    }

    private func loadLocal(_ url: URL) -> PreviewImageView.LoadState {
        let manager = FileManager.default
        // **ファイル単体で判じない。** サンドボックスに阻まれると、
        // 「読めない」ではなく「そもそも無い」ように見えることがある
        // （`fileExists` が false を返す）。そのまま「見つかりません」と出すと、
        // 許可すれば直る場合でも、利用者に打つ手が無くなる。
        //
        // 置かれているフォルダを読めるかどうかで分ける。
        // フォルダが読めないなら、ファイルの見え方に関わらず許可の問題。
        let folderIsReadable = manager.isReadableFile(atPath: url.deletingLastPathComponent().path)

        guard manager.fileExists(atPath: url.path) else {
            return .failed(folderIsReadable ? .notFound : .noPermission)
        }
        guard manager.isReadableFile(atPath: url.path) else { return .failed(.noPermission) }
        guard let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) else {
            return .failed(folderIsReadable ? .unreadable : .noPermission)
        }
        cache[url] = image
        return .loaded(image)
    }

    private func loadRemote(_ url: URL) async -> PreviewImageView.LoadState {
        guard let (data, response) = try? await URLSession.shared.data(from: url) else {
            return .failed(.unreadable)
        }
        guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
              let image = PlatformImage(data: data)
        else { return .failed(.unreadable) }
        cache[url] = image
        return .loaded(image)
    }
}
