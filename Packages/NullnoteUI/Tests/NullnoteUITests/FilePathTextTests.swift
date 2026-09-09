import Foundation
import Testing
@testable import NullnoteUI

/// 開いているファイルの場所を、貼り付けられる文字列にする（#025）。
@Suite("パスの文字列")
struct FilePathTextTests {

    @Test("絶対パスは、そのまま端末に渡せる形で出す")
    func absolute() {
        let url = URL(fileURLWithPath: "/Users/foo/Develop/docs/note.md")
        #expect(FilePathText.absolute(url) == "/Users/foo/Develop/docs/note.md")
    }

    @Test("`~` には縮めない")
    func noTilde() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let url = home.appendingPathComponent("note.md")
        #expect(FilePathText.absolute(url).hasPrefix("/"))
        #expect(!FilePathText.absolute(url).hasPrefix("~"))
    }

    @Test("フォルダのパスは、末尾に区切りを付けない")
    func folder() {
        let url = URL(fileURLWithPath: "/Users/foo/Develop/docs/note.md")
        #expect(FilePathText.folder(url) == "/Users/foo/Develop/docs")
    }

    @Test("根っこに置かれたファイルでも、フォルダは `/` のまま")
    func folderAtRoot() {
        #expect(FilePathText.folder(URL(fileURLWithPath: "/note.md")) == "/")
    }

    @Test("ファイル名は拡張子まで出す")
    func name() {
        let url = URL(fileURLWithPath: "/Users/foo/docs/判断の記録.md")
        #expect(FilePathText.name(url) == "判断の記録.md")
    }

    @Test("空白や日本語が入っていても、逃がし記号を混ぜない")
    func noPercentEncoding() {
        let url = URL(fileURLWithPath: "/Users/foo/My Notes/日本語 の 記録.md")
        #expect(FilePathText.absolute(url) == "/Users/foo/My Notes/日本語 の 記録.md")
        #expect(FilePathText.folder(url) == "/Users/foo/My Notes")
        #expect(FilePathText.name(url) == "日本語 の 記録.md")
    }

    @Test("`..` や `.` を含む道筋は、辿り直した形にする")
    func standardized() {
        let url = URL(fileURLWithPath: "/Users/foo/docs/../docs/./note.md")
        #expect(FilePathText.absolute(url) == "/Users/foo/docs/note.md")
        #expect(FilePathText.folder(url) == "/Users/foo/docs")
    }
}
