import Foundation
import Testing
@testable import NullnoteUI

/// 外でファイルが書き換わったときの判断。
///
/// **失ってはいけないのは、こちらの直し。保存したかどうかは関係ない。**
/// `DocumentGroup` は打鍵の1秒ほど後に勝手に保存するので、
/// 「未保存のときだけ守る」形では守れない（D-35）。
/// 取り込んでよい場面と、人に聞くべき場面を取り違えないことを縛る。
@Suite("外の変更をどう扱うか")
struct ExternalChangeTests {

    @Test("相手が見た版から動いていなければ取り込む")
    func reloadsWhenUntouched() {
        // Claude Code などで書き換えたとき、いちばん多い場面。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "外で書いた内容", editor: "もとの内容", lastExternal: "もとの内容"
            ) == .reload("外で書いた内容")
        )
    }

    @Test("中身が同じなら何もしない")
    func ignoresIdenticalContents() {
        // 自分で保存した直後にも見張りは反応する。ここで落とさないと、
        // 保存のたびに取り込みが走る。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "同じ内容", editor: "同じ内容", lastExternal: "もとの内容"
            ) == .ignore
        )
    }

    @Test("基準が分からないときは、そのまま取り込む")
    func reloadsWhenBaseUnknown() {
        // 開いた直後に基準を置くので、ここに来るのは事故のとき。
        // 基準が無いと「どちらが直したのか」を区別できず、
        // 突き合わせても全体が1つの競合になるだけで、かえって読めない。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "外で書いた内容", editor: "書きかけの内容"
            ) == .reload("外で書いた内容")
        )
    }

    // MARK: - 突き合わせに回す場面

    @Test("書きかけがあれば、勝手に取り込まず突き合わせに回す")
    func mergesInsteadOfOverwriting() {
        // ここで取り込むと、書きかけが黙って消える。**いちばんやってはいけない。**
        #expect(
            ExternalChangeResolver.resolve(
                disk: "外で書いた内容", editor: "書きかけの内容", lastExternal: "もとの内容"
            ) == .merge(base: "もとの内容", ours: "書きかけの内容", theirs: "外で書いた内容")
        )
    }

    /// **保存済みでも守る。** これがこの設計の要点。
    ///
    /// 打った直後に自動保存が走り、その後で外から古い基準の書き込みが来る、
    /// という並びが実際に起きる（D-34 で文字を消した）。
    /// 基準を自分の保存で進めていないので、ここは突き合わせに入る。
    @Test("自分が保存した後でも、相手が見た版から動いていれば突き合わせる")
    func mergesEvenAfterOurOwnSave() {
        #expect(
            ExternalChangeResolver.resolve(
                disk: "外が古い版から書いた内容",
                editor: "保存済みのこちらの直し",
                lastExternal: "相手が最後に見た版"
            ) == .merge(
                base: "相手が最後に見た版",
                ours: "保存済みのこちらの直し",
                theirs: "外が古い版から書いた内容"
            )
        )
    }

    @Test("空のファイルにされても、こちらが動いていれば取り込まない")
    func doesNotReloadWhenFileEmptied() {
        // 外のツールが失敗して空にしてしまうことがある。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "", editor: "書きかけの内容", lastExternal: "もとの内容"
            ) == .merge(base: "もとの内容", ours: "書きかけの内容", theirs: "")
        )
    }

    @Test("こちらが動いていなければ、空にされたことも取り込む")
    func reloadsEmptyWhenUntouched() {
        // 判断しない。ディスクが正であることに変わりはない。
        #expect(
            ExternalChangeResolver.resolve(
                disk: "", editor: "もとの内容", lastExternal: "もとの内容"
            ) == .reload("")
        )
    }

    // MARK: - 見張りを張り直すときの基準

    /// 画面が組み直されただけで基準を動かすと、未保存の編集が黙って消える（#024）。
    ///
    /// `.task(id: fileURL)` はファイルが変わったときだけでなく、
    /// ビューが現れ直すたびにも走る。そこを縛る。
    @Suite("見張りを張り直すときの基準")
    struct BaselineTests {

        private let file = URL(fileURLWithPath: "/tmp/a.md")
        private let another = URL(fileURLWithPath: "/tmp/b.md")

        @Test("同じファイルを見張り直すだけなら、基準は動かさない")
        func keepsBaselineForSameFile() {
            #expect(
                ExternalChangeResolver.baseline(
                    watched: file, opening: file,
                    disk: "ディスクの内容", editor: "書きかけ"
                ) == .keep
            )
        }

        @Test("はじめて見張るときは、ディスクの内容を基準にする")
        func takesBaselineFromDisk() {
            // **編集画面ではなくディスク。** 基準の意味は
            // 「外の世界が最後に見たはずの内容」。
            #expect(
                ExternalChangeResolver.baseline(
                    watched: nil, opening: file,
                    disk: "ディスクの内容", editor: "書きかけ"
                ) == .replace("ディスクの内容")
            )
        }

        @Test("別のファイルになったら、そちらのディスクを基準にする")
        func rebasesOnAnotherFile() {
            // 改名・別名で保存でここを通る。
            #expect(
                ExternalChangeResolver.baseline(
                    watched: file, opening: another,
                    disk: "別のファイルの内容", editor: "書きかけ"
                ) == .replace("別のファイルの内容")
            )
        }

        @Test("ディスクが読めないときだけ、編集画面を頼る")
        func fallsBackToEditor() {
            #expect(
                ExternalChangeResolver.baseline(
                    watched: nil, opening: file, disk: nil, editor: "書きかけ"
                ) == .replace("書きかけ")
            )
        }

        @Test("同じファイルなら、ディスクを読みに行かない")
        func doesNotReadDiskWhenKeeping() {
            // 見張りの張り直しは画面が現れるたびに通る。
            // そのたびに 100 KB を読み直すのでは割に合わない。
            nonisolated(unsafe) var reads = 0
            _ = ExternalChangeResolver.baseline(
                watched: file, opening: file,
                disk: { reads += 1; return "ディスクの内容" }(), editor: "書きかけ"
            )
            #expect(reads == 0)
        }
    }

    // MARK: - 組み直しのあとに外から書かれる

    /// #024 そのもの。**基準の置き方だけで、消えるか印が出るかが変わる。**
    @Test("組み直しで基準を編集画面にすると、外の変更が印なしで差し替わる")
    func rebuildingWithEditorTextLosesEdits() {
        // 画面が組み直された時点の編集画面（未保存の直しが乗っている）
        let editor = "- A こちらの直し\n"
        // 誤った置き方: 基準 = 編集画面
        #expect(
            ExternalChangeResolver.resolve(
                disk: "- A 外の直し\n", editor: editor, lastExternal: editor
            ) == .reload("- A 外の直し\n")
        )
    }

    @Test("組み直しで基準をディスクにすれば、突き合わせに回る")
    func rebuildingWithDiskTextKeepsEdits() {
        let onDisk = "- A\n"
        let editor = "- A こちらの直し\n"
        // 正しい置き方: 基準 = そのときのディスク
        #expect(
            ExternalChangeResolver.resolve(
                disk: "- A 外の直し\n", editor: editor, lastExternal: onDisk
            ) == .merge(base: onDisk, ours: editor, theirs: "- A 外の直し\n")
        )
    }

    // MARK: - 判断から結果まで

    /// 判断と突き合わせをつないで、**実際に何が残るか**まで見る。
    ///
    /// 今日いちばん確かめたい並びはこれ。
    /// 1. 外（Claude Code）がファイルを読む
    /// 2. こちらが打って、自動保存が走る
    /// 3. 外が**古い内容を基準に**書く
    private func outcome(base: String, editor: String, disk: String) -> ThreeWayMerge.Result? {
        guard case .merge(let b, let o, let t) = ExternalChangeResolver.resolve(
            disk: disk, editor: editor, lastExternal: base
        ) else { return nil }
        return ThreeWayMerge.merge(base: b, ours: o, theirs: t)
    }

    @Test("古い版から書かれても、違う行なら両方残る")
    func staleWriteKeepsBothEdits() {
        let result = outcome(
            base:   "- A\n- B\n",
            editor: "- A 直した\n- B\n",        // こちらの直し（保存済み）
            disk:   "- A\n- B 直した\n"         // 外が古い版から書いた
        )
        #expect(result?.text == "- A 直した\n- B 直した\n")
        #expect(result?.hasConflicts == false)
    }

    @Test("古い版から同じ行を書かれたら、印が入る")
    func staleWriteOnSameLineConflicts() {
        let result = outcome(
            base:   "- A\n- B\n",
            editor: "- A こちらの直し\n- B\n",
            disk:   "- A 外の直し\n- B\n"
        )
        #expect(result?.conflictCount == 1)
        // **どちらも消えていない。** 選ぶのは人。
        #expect(result?.text.contains("- A こちらの直し") == true)
        #expect(result?.text.contains("- A 外の直し") == true)
    }

    @Test("外が最新を読んでから書いていれば、印は出ない")
    func upToDateWriteDoesNotConflict() {
        // 外がこちらの直しを取り込んだ上で書いた場合。
        // 同じ直しが両側にあるので、競合にはならない。
        let result = outcome(
            base:   "- A\n- B\n",
            editor: "- A 直した\n- B\n",
            disk:   "- A 直した\n- B 外が足した\n"
        )
        #expect(result?.text == "- A 直した\n- B 外が足した\n")
        #expect(result?.hasConflicts == false)
    }
}
