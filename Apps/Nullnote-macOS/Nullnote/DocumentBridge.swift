import AppKit

/// SwiftUI の `DocumentGroup` が裏で持っている `NSDocument` に触るための窓口。
///
/// SwiftUI は書類の状態（未保存かどうか、ファイルの更新日時）を公開していない。
/// 一方で実体はふつうの `NSDocument` の派生
/// （`FileWrapperPlatformDocument → PlatformDocument → NSDocument`）で、
/// `NSDocumentController` から素直に取れる。**私有 API は使っていない。**
///
/// ここでしか AppKit の書類機構に触らない。増やすときは本当に要るか一度立ち止まること。
@MainActor
enum DocumentBridge {

    /// その URL を開いている書類。
    static func document(for url: URL) -> NSDocument? {
        NSDocumentController.shared.documents.first { document in
            guard let opened = document.fileURL else { return false }
            // 同じファイルでも表記が違うことがある（シンボリックリンク、大文字小文字）。
            return opened.standardizedFileURL == url.standardizedFileURL
        }
    }

    /// 保存していない編集があるか。
    ///
    /// 自前で「最後に読んだ内容」と比べる手もあるが、
    /// 取り消し（⌘Z）で元に戻した場合など、判断がずれる。`NSDocument` に聞く。
    static func hasUnsavedChanges(at url: URL) -> Bool {
        document(for: url)?.isDocumentEdited ?? false
    }

    /// 外の変更を取り込んだあとの後始末。
    ///
    /// **これをやらないと、内容は最新なのに競合ダイアログだけ出続ける。**
    /// `NSDocument` は「最後に読み書きしたときのファイルの更新日時」を覚えていて、
    /// 保存時にディスクの値と突き合わせる。取り込んだのだから、合わせておく。
    ///
    /// 併せて変更の数え上げも戻す。取り込んだ内容はディスクと同じなので、
    /// 「未保存の変更あり」のままにしておく理由が無い。
    static func acceptExternalContents(at url: URL) {
        syncModificationDate(at: url)
        document(for: url)?.updateChangeCount(.changeCleared)
    }

    /// 「外で書き換えられた」という判定だけを外す。
    ///
    /// 合流したときに使う。合流の結果は**まだ保存されていない編集**なので、
    /// 変更の数え上げは戻さない。戻すと、印の付いた本文が未保存だと分からなくなる。
    static func syncModificationDate(at url: URL) {
        guard let document = document(for: url) else { return }
        document.fileModificationDate = modificationDate(of: url)
    }

    /// 書類のファイル名を変える。
    ///
    /// **`FileManager` で動かさない。** 書類は自分の `fileURL` を握っていて、
    /// 黙って動かすと以後の保存が消えた場所に書きに行く。`NSDocument` に頼めば、
    /// ファイルの移動と `fileURL` の更新が一組で行われる。
    ///
    /// 失敗しても何もしない（名前が変わらないだけ）。上書きの恐れがある場面は、
    /// 呼ぶ側で先に弾いている。
    static func rename(at url: URL, to destination: URL) {
        document(for: url)?.move(to: destination)
    }

    /// 競合ダイアログが出る条件を、画面を見ずに確かめるための足あと。
    ///
    /// `NSDocument` は「最後に読み書きしたときのファイルの更新日時」を覚えていて、
    /// 保存時にディスクの値と突き合わせる。**ここがずれていると警告が出る。**
    /// 取り込み・合流のあとにこれが揃っているかどうかが、そのまま合否になる。
    static func stateDescription(at url: URL) -> String {
        guard let document = document(for: url) else { return "書類が見つからない" }
        let recorded = document.fileModificationDate
        let disk = modificationDate(of: url)
        return "編集済み=\(document.isDocumentEdited) 日時一致=\(recorded == disk)"
    }

    private static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}
