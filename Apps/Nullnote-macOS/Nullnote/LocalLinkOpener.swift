import AppKit
import NullnoteUI

/// プレビューの、手元のファイルへのリンクを開く（#013）。
///
/// `.md`・`.markdown` は Nullnote で開く。それ以外のファイルは既定のアプリに任せる。
/// フォルダならそのフォルダを Finder で開く。
///
/// サンドボックスの中なので、**リンク先のフォルダは読めないことが多い**（画像と同じ）。
/// 読めなければ、画像と同じやり方でフォルダの閲覧を頼む（`FolderAccess`）。
@MainActor
enum LocalLinkOpener {

    static func open(_ target: URL) {
        Task { await openAfterAccess(target) }
    }

    private static func openAfterAccess(_ target: URL) async {
        let folder = target.deletingLastPathComponent()
        guard await FolderAccess.requestForLink(to: folder) else { return }

        let fileManager = FileManager.default
        guard let found = PreviewLinkResolver.candidates(for: target)
            .first(where: { fileManager.fileExists(atPath: $0.path) })
        else {
            Trace.log("リンク: 見つからない \(target.path)")
            showNotFound(target)
            return
        }

        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: found.path, isDirectory: &isDirectory)
        if isDirectory.boolValue {
            NSWorkspace.shared.open(found)
        } else if PreviewLinkResolver.isMarkdown(found) {
            // すでに開いていれば、その窓が前に出る。
            do {
                _ = try await NSDocumentController.shared.openDocument(withContentsOf: found, display: true)
            } catch {
                Trace.log("リンク: 開けない \(found.path) \(error)")
                NSAlert(error: error).runModal()
            }
        } else {
            NSWorkspace.shared.open(found)
        }
    }

    private static func showNotFound(_ target: URL) {
        let alert = NSAlert()
        alert.messageText = String(localized: "リンク先のファイルが見つかりません。")
        alert.informativeText = target.path
        alert.runModal()
    }
}
