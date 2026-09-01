import NullnoteUI
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Markdown には Apple 定義の UTType が無い。Info.plist で
    /// `net.daringfireball.markdown` を Imported Type Identifier として宣言し、
    /// ここで参照する。宣言を消すと `.md` を開けないアプリになる。
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}

struct MarkdownDocument: FileDocument {

    var text: String

    init(text: String = "") {
        self.text = text
    }

    static let readableContentTypes: [UTType] = [.markdown, .plainText]
    static let writableContentTypes: [UTType] = [.markdown]

    init(configuration: ReadConfiguration) throws {
        Trace.mark("書類の読み込み開始")
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // UTF-8 で読めなければ、既定のテキストエンコーディングに落とす。
        // どちらでも読めないものは無理に化けさせず、エラーにする。
        if let utf8 = String(data: data, encoding: .utf8) {
            text = utf8
        } else if let fallback = String(data: data, encoding: .isoLatin1) {
            text = fallback
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        Trace.mark("書類の読み込み完了 \(text.count)文字")
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
