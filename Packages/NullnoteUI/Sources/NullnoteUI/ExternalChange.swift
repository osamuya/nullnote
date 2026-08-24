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
    ///   - lastExternal: **外の世界が最後に見たはずの内容。** 合流の基準にする。
    ///     開いた時と、外の変更を取り込んだ時にだけ進める。
    ///     **自分で保存しても進めない**（理由は下）。分からないときは `nil`。
    ///
    /// ## なぜ「未保存かどうか」で決めないか
    ///
    /// `DocumentGroup` は打鍵の1秒ほど後に勝手に保存する。
    /// 「未保存の編集があるときだけ合流する」形にすると、その窓はほとんど開かない。
    /// 外から書く道具（Claude Code など）が**古い内容を基準に**書いてきたとき、
    /// こちらの直しが黙って消える（実測。D-34 / D-35）。
    ///
    /// 基準を自分の保存で進めないでおけば、保存したかどうかに関係なく
    /// 「相手が見ていた版」と「こちらの直し」を突き合わせられる。
    ///
    /// **誤検知は起きにくい。** 相手が最新を読んでから書いていれば、
    /// こちらの直しは相手の内容にも入っている。`ThreeWayMerge` はそれを
    /// 「同じ直し方をしていた」と見て、印を出さない。
    public static func resolve(
        disk: String, editor: String, lastExternal: String? = nil
    ) -> ExternalChange {
        // 中身が同じなら、何が起きていても関係ない。
        // 自分で保存した直後にも見張りが反応するので、まずここで落とす。
        guard disk != editor else { return .ignore }

        // 相手が見た版から、こちらは何も動かしていない。
        // 画面はディスクの写しでしかないので、差し替えても失うものが無い。
        guard let base = lastExternal, base != editor else { return .reload(disk) }

        return .merge(base: base, ours: editor, theirs: disk)
    }
}
