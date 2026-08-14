import Testing
@testable import NullnoteUI

/// 外でファイルが書き換わったときの判断。
///
/// **失ってはいけないのは、編集中の内容だけ。**
/// 取り込んでよい場面と、人に聞くべき場面を取り違えないことを縛る。
@Suite("外の変更をどう扱うか")
struct ExternalChangeTests {

    @Test("編集していなければ取り込む")
    func reloadsWhenUntouched() {
        // Claude Code などで書き換えたとき、いちばん多い場面。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "外で書いた内容", editor: "もとの内容", hasLocalEdits: false
            ) == .reload("外で書いた内容")
        )
    }

    @Test("中身が同じなら何もしない")
    func ignoresIdenticalContents() {
        // 自分で保存した直後にも見張りは反応する。ここで落とさないと、
        // 保存のたびに取り込みが走る。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "同じ内容", editor: "同じ内容", hasLocalEdits: false
            ) == .ignore
        )
    }

    @Test("編集していても、中身が同じなら何もしない")
    func ignoresIdenticalContentsEvenWhenEdited() {
        // 編集した結果がたまたまディスクと同じになった場合。
        // 競合として扱う理由が無い。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "同じ内容", editor: "同じ内容", hasLocalEdits: true
            ) == .ignore
        )
    }

    @Test("編集中なら勝手に取り込まず、突き合わせに回す")
    func mergesInsteadOfOverwriting() {
        // ここで取り込むと、書きかけが黙って消える。**いちばんやってはいけない。**
        #expect(
            ExternalChangeResolver.resolve(
                disk: "外で書いた内容", editor: "書きかけの内容",
                hasLocalEdits: true, lastSynced: "もとの内容"
            ) == .merge(base: "もとの内容", ours: "書きかけの内容", theirs: "外で書いた内容")
        )
    }

    @Test("基準が分からないときは、編集中の内容を基準にする")
    func fallsBackToEditorAsBase() {
        // 基準が無いと「どちらが直したのか」を区別できない。
        // 編集中の内容を基準に置けば、外の直しだけが差として出る。
        // 取りこぼすより、多めに印を付ける方に倒す。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "外で書いた内容", editor: "書きかけの内容", hasLocalEdits: true
            ) == .merge(base: "書きかけの内容", ours: "書きかけの内容", theirs: "外で書いた内容")
        )
    }

    @Test("空のファイルにされても、編集中なら取り込まない")
    func doesNotReloadWhenFileEmptied() {
        // 外のツールが失敗して空にしてしまうことがある。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "", editor: "書きかけの内容", hasLocalEdits: true, lastSynced: "もとの内容"
            ) == .merge(base: "もとの内容", ours: "書きかけの内容", theirs: "")
        )
    }

    @Test("編集していなければ、空にされたことも取り込む")
    func reloadsEmptyWhenUntouched() {
        // 判断しない。ディスクが正であることに変わりはない。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "", editor: "もとの内容", hasLocalEdits: false
            ) == .reload("")
        )
    }
}
