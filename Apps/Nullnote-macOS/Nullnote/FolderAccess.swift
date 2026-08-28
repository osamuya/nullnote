import AppKit
import NullnoteUI

/// フォルダを読む許可を、利用者から一度だけもらって覚えておく。
///
/// このアプリはサンドボックスの中にいて、**利用者が明示的に選んだものしか読めない**。
/// 文書を開いても、その隣にある画像は読めない（実測で確認）。
///
/// 読むには、利用者にフォルダを選んでもらい、その範囲を
/// **セキュリティスコープ付きブックマーク**として保存する。
/// これは App Store に出せるやり方で、サンドボックスを外す必要はない。
///
/// ## 一度きりにする
///
/// 許可をもらったら保存し、次の起動時に開き直す。
/// 画像を見るたびに聞かれるのでは使い物にならない。
@MainActor
enum FolderAccess {

    private static let storageKey = "grantedFolderBookmarks"

    /// 起動時に呼ぶ。前に許可をもらったフォルダを、また読めるようにする。
    static func restoreAll() {
        for (path, data) in stored() {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { continue }

            // 開いたら閉じない。アプリが動いているあいだ読めるようにしておく。
            let opened = url.startAccessingSecurityScopedResource()
            Trace.log("FolderAccess: 復帰 \(path) 開けた=\(opened) 古い=\(isStale)")

            // 引っ越しなどで古くなっていたら、取り直して保存し直す。
            if isStale, let fresh = bookmark(for: url) {
                save(fresh, for: path)
            }
        }
    }

    /// フォルダの閲覧を頼む。画像を読むため。
    ///
    /// - Returns: 許可されたら `true`。
    static func request(for folder: URL) async -> Bool {
        await request(
            for: folder,
            message: "「\(folder.lastPathComponent)」の中の画像を表示するために、このフォルダの閲覧を許可してください。",
            isSatisfied: { FileManager.default.isReadableFile(atPath: $0.path) }
        )
    }

    /// フォルダに書き込む許可を頼む。ファイル名を付け直すため。
    ///
    /// **読めるだけでは足りない。** 改名はフォルダの項目を書き換える操作なので、
    /// 書類そのものへの許可（開いたときにもらえる）では通らない。実測で確かめた。
    ///
    /// - Returns: 許可されたら `true`。
    static func requestWriting(for folder: URL) async -> Bool {
        await request(
            for: folder,
            message: "見出しに合わせてファイル名を付け直すために、「\(folder.lastPathComponent)」への書き込みを許可してください。",
            isSatisfied: { FileManager.default.isWritableFile(atPath: $0.path) }
        )
    }

    private static func request(
        for folder: URL,
        message: String,
        isSatisfied: (URL) -> Bool
    ) async -> Bool {
        // すでに足りているなら聞かない。
        if isSatisfied(folder) { return true }

        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "許可"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        // 迷わせないよう、頼んだフォルダを最初から選んだ状態にする。
        panel.nameFieldStringValue = folder.lastPathComponent

        guard await panel.begin() == .OK, let granted = panel.url else {
            Trace.log("FolderAccess: 許可されなかった \(folder.path)")
            return false
        }

        _ = granted.startAccessingSecurityScopedResource()
        if let data = bookmark(for: granted) {
            save(data, for: granted.path)
            Trace.log("FolderAccess: 覚えた \(granted.path) \(data.count)バイト")
        }
        return isSatisfied(folder)
    }

    // MARK: - 覚えておく

    /// セキュリティスコープ付きブックマークを作る。
    ///
    /// **`com.apple.security.files.bookmarks.app-scope` が無いと、ここが必ず失敗する。**
    /// 握り潰すと「毎回フォルダを聞き直される」という形でしか表に出ず、原因が見えない。
    /// 足あとに残す（`NULLNOTE_TRACE=1`）。
    private static func bookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
            )
        } catch {
            Trace.log("FolderAccess: ブックマークを作れない \(url.path) \(error)")
            return nil
        }
    }

    private static func stored() -> [String: Data] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Data] ?? [:]
    }

    private static func save(_ data: Data, for path: String) {
        var all = stored()
        all[path] = data
        UserDefaults.standard.set(all, forKey: storageKey)
    }
}
