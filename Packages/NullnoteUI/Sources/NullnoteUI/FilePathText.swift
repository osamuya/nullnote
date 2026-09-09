import Foundation

/// 開いているファイルの場所を、貼り付けられる文字列にする。
///
/// **アプリ側は、ここで作った文字列を貼り板に載せるだけ。**
/// `NullnoteUI` は書類も Finder も知らない（D-45）が、
/// URL から文字を作るだけならここに置ける。試験の的を置ける場所がここしかない。
///
/// Nullnote には「プロジェクト」が無いので、**相対パスは作らない**。
/// 何を基準にした相対かを決められないため（#025 の相談で確認済み）。
public enum FilePathText {

    /// 絶対パス。`/Users/foo/Develop/docs/note.md`
    ///
    /// **`~` に縮めない。** 端末や別の道具にそのまま渡せる形にする。
    /// Finder の「パス名としてコピー」（⌥⌘C）と同じ形。
    public static func absolute(_ url: URL) -> String {
        url.standardizedFileURL.path
    }

    /// そのファイルが入っているフォルダのパス。`/Users/foo/Develop/docs`
    ///
    /// **末尾に `/` は付けない。** `cd` にそのまま渡せる形にする。
    public static func folder(_ url: URL) -> String {
        let parent = url.standardizedFileURL.deletingLastPathComponent().path
        // 根っこ（`/`）だけは1文字で、削ると空になる。
        guard parent.count > 1, parent.hasSuffix("/") else { return parent }
        return String(parent.dropLast())
    }

    /// ファイル名だけ。拡張子を含む。`note.md`
    public static func name(_ url: URL) -> String {
        url.lastPathComponent
    }
}
