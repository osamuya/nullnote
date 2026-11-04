import Foundation
import SwiftUI

/// プレビューでクリックされたリンクの行き先（#013）。
public enum PreviewLinkTarget: Equatable {
    /// 手元のファイル。文書を基準に解決したあとの場所。まだあるかどうかは見ていない。
    case local(URL)
    /// `https:`・`mailto:` など。OS に任せる。
    case external(URL)
}

/// リンクに書かれた場所を解釈する。
///
/// **書き方は画像と同じく全部認める**（`ImageSourceResolver`）。相対パス・`~/`・絶対パス・`file:`。
/// 相対パスを OS にそのまま渡すと、基準が無いので「アプリケーションを開けません。-50」になる。
///
/// 副作用を持たない。ファイルがあるかどうかも見ない（サンドボックスの許可が要るため、開く側で見る）。
public enum PreviewLinkResolver {

    /// - Parameters:
    ///   - link: リンクの URL（`PreviewModel` が `link.destination` から作ったもの）。
    ///   - document: 文書のファイル。相対パスの基準にする。新規で未保存なら `nil`。
    /// - Returns: 行き先。文書内の見出しへのリンク（`#…` だけ）や、基準が無くて決められないときは `nil`。
    public static func resolve(_ link: URL, relativeTo document: URL?) -> PreviewLinkTarget? {
        if let scheme = link.scheme?.lowercased(), scheme != "file" {
            return .external(link)
        }

        // `#見出し` や `?…` はファイルの場所ではないので外す。
        var written = link.relativeString
        if let cut = written.firstIndex(where: { $0 == "#" || $0 == "?" }) {
            written = String(written[..<cut])
        }
        guard !written.isEmpty else { return nil }

        guard case let .local(url)? = ImageSourceResolver.resolve(written, relativeTo: document) else {
            return nil
        }
        return .local(url)
    }

    /// 実際に探す順。
    ///
    /// 拡張子を書かずに `[目次](./株取引)` とつなぐ書き方がある（Wiki 風の書き方）。
    /// 拡張子が無ければ、書いたとおりの名前のあとに `.md`・`.markdown` を試す。
    public static func candidates(for url: URL) -> [URL] {
        guard url.pathExtension.isEmpty else { return [url] }
        return [url] + markdownExtensions.map { url.appendingPathExtension($0) }
    }

    /// Nullnote で開く拡張子。Info.plist の `net.daringfireball.markdown` と揃える。
    public static let markdownExtensions = ["md", "markdown"]

    /// Nullnote で開くファイルか。
    public static func isMarkdown(_ url: URL) -> Bool {
        markdownExtensions.contains(url.pathExtension.lowercased())
    }
}

/// 手元のファイルへのリンクがクリックされたときに開く手立て。
///
/// **開き方はアプリ側が持つ。** フォルダの許可の頼み方も、書類の開き方も AppKit と結び付いている。
public struct PreviewLinkOpener: Sendable {
    /// 文書を基準に解決した場所を受け取る。ファイルがあるかはまだ見ていない。
    public let open: @MainActor @Sendable (URL) -> Void

    public init(open: @escaping @MainActor @Sendable (URL) -> Void) {
        self.open = open
    }
}

private struct PreviewLinkActionKey: EnvironmentKey {
    static let defaultValue: PreviewLinkAction? = nil
}

/// リンクがクリックされたときの振る舞い。`PreviewText` が受け取る。
struct PreviewLinkAction: Sendable {
    /// - Returns: こちらで扱ったら `true`。`false` なら OS に任せる。
    let handle: @MainActor @Sendable (URL) -> Bool
}

extension EnvironmentValues {
    var previewLinkAction: PreviewLinkAction? {
        get { self[PreviewLinkActionKey.self] }
        set { self[PreviewLinkActionKey.self] = newValue }
    }
}
