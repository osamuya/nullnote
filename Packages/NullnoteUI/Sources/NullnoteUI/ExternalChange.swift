import Foundation

/// 外でファイルが書き換わったときに、どうするか。
public enum ExternalChange: Equatable {
    /// 何もしない。中身が同じか、見るべき差が無い。
    case ignore
    /// ディスクの内容をそのまま取り込む。**編集中のものが無いので、失うものが無い。**
    case reload(String)
    /// 編集中のものと食い違っている。突き合わせて合流する。
    ///
    /// 重ならない直しは黙って取り込まれ、同じところを直していた箇所にだけ印が入る。
    case merge(base: String, ours: String, theirs: String)
}

/// 外の変更をどう扱うかを決める。
///
/// **副作用を持たない。** ファイルも書類も触らない。
/// 「取り込んでよいか」の判断だけをここに集めて、テストで縛る。
public enum ExternalChangeResolver {

    /// - Parameters:
    ///   - disk: いまディスクにある内容。
    ///   - editor: 編集画面にある内容。
    ///   - hasLocalEdits: 保存していない編集があるか（`NSDocument` に聞く）。
    ///   - lastSynced: 最後に双方が一致していた内容。合流の基準にする。
    ///     分からないときは `nil`。基準が無いと、どちらの直しか区別できない。
    public static func resolve(
        disk: String, editor: String, hasLocalEdits: Bool, lastSynced: String? = nil
    ) -> ExternalChange {
        // 中身が同じなら、何が起きていても関係ない。
        // 自分で保存した直後にも見張りが反応するので、まずここで落とす。
        guard disk != editor else { return .ignore }

        // 編集中のものが無い＝画面はディスクの写しでしかない。
        // 差し替えても失うものが無いので、黙って取り込む。
        guard hasLocalEdits else { return .reload(disk) }

        // 両方が変わっている。突き合わせて合流する。
        //
        // 基準が無いときは、編集中の内容を基準にするしかない。
        // そうすると自分の直しが「基準」に混ざるので、外の直しだけが差として出る。
        // 取りこぼすより、多めに印を付ける方に倒す。
        return .merge(base: lastSynced ?? editor, ours: editor, theirs: disk)
    }
}
