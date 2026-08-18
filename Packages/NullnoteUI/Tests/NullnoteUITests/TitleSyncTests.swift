import Testing
@testable import NullnoteUI

/// ファイル名と先頭の見出しを揃える判断。
///
/// **黙って本文を書き換える機能なので、触る範囲を厳しく縛る。**
/// 触ってよいのは1行目だけ。それ以外の行は、どの場面でも動かない。
@Suite("ファイル名と見出しの同期")
struct TitleSyncTests {

    // MARK: - 見出しの文字列

    @Test("拡張子を落とす")
    func dropsExtension() {
        #expect(TitleSync.title(fromFileName: "メモ.md") == "メモ")
        #expect(TitleSync.title(fromFileName: "議事録.markdown") == "議事録")
        // 途中の点は落とさない。落とすのは最後の拡張子だけ。
        #expect(TitleSync.title(fromFileName: "v1.2 案.md") == "v1.2 案")
        // 拡張子が無ければそのまま。
        #expect(TitleSync.title(fromFileName: "メモ") == "メモ")
    }

    // MARK: - 先頭に見出しがある

    @Test("先頭の見出しを差し替える")
    func replacesLeadingHeading() {
        #expect(
            TitleSync.applying(fileName: "新しい名前.md", to: "# 古い名前\n\n本文\n")
                == "# 新しい名前\n\n本文\n"
        )
    }

    @Test("同じ名前なら何もしない")
    func ignoresSameTitle() {
        // 名前を変えずに別のフォルダへ移しただけのときも、ここに来る。
        #expect(TitleSync.applying(fileName: "メモ.md", to: "# メモ\n\n本文\n") == nil)
    }

    @Test("空行が先にあっても、その見出しを差し替える")
    func replacesHeadingAfterBlankLines() {
        #expect(
            TitleSync.applying(fileName: "新題.md", to: "\n\n# 旧題\n本文\n")
                == "\n\n# 新題\n本文\n"
        )
    }

    @Test("閉じの # は残す")
    func keepsClosingSequence() {
        #expect(
            TitleSync.applying(fileName: "新題.md", to: "# 旧題 #\n本文\n")
                == "# 新題 #\n本文\n"
        )
    }

    @Test("# だけの行にも入れられる")
    func fillsEmptyHeading() {
        #expect(TitleSync.applying(fileName: "新題.md", to: "#\n本文\n") == "# 新題\n本文\n")
        #expect(TitleSync.applying(fileName: "新題.md", to: "#  \n本文\n") == "# 新題\n本文\n")
    }

    @Test("見出しの中の記法は残さない")
    func replacesDecoratedHeading() {
        // `# **旧題**` → `# 新題`。同期を選んだ以上、見出しの中身はファイル名で決まる。
        #expect(TitleSync.applying(fileName: "新題.md", to: "# **旧題**\n") == "# 新題\n")
    }

    @Test("記法を落とすと同じなら、太字を剥がすためだけに書き換えない")
    func ignoresDecoratedHeadingWithSameText() {
        // 逆方向（見出し → ファイル名）で `# **企画**` から `企画.md` を作った直後、
        // 順方向がここで止まらないと、太字を剥がす書き換えが起きて往復する。
        #expect(TitleSync.applying(fileName: "企画.md", to: "# **企画**\n") == nil)
    }

    // MARK: - 先頭に見出しがない

    @Test("見出しが無ければ先頭に挿し込む")
    func insertsHeading() {
        #expect(TitleSync.applying(fileName: "新題.md", to: "本文\n") == "# 新題\n\n本文\n")
    }

    @Test("空の文書にも挿し込む")
    func insertsIntoEmptyDocument() {
        #expect(TitleSync.applying(fileName: "新題.md", to: "") == "# 新題\n")
    }

    @Test("すでに空行で始まっていれば、空行を増やさない")
    func doesNotAddBlankLineTwice() {
        #expect(TitleSync.applying(fileName: "新題.md", to: "\n本文\n") == "# 新題\n\n本文\n")
    }

    @Test("## は先頭のタイトルとして扱わない")
    func ignoresDeeperHeading() {
        // レベル2以下は「先頭の # のタイトル」ではない。上に挿し込む。
        #expect(
            TitleSync.applying(fileName: "新題.md", to: "## 節\n本文\n")
                == "# 新題\n\n## 節\n本文\n"
        )
    }

    // MARK: - 見出しに見えるが見出しではない行

    @Test("コードブロックの中の # は書き換えない")
    func ignoresHeadingInsideCodeFence() {
        let source = "```sh\n# これはコメント\n```\n"
        #expect(TitleSync.applying(fileName: "新題.md", to: source) == "# 新題\n\n" + source)
    }

    @Test("引用の中の # は書き換えない")
    func ignoresHeadingInsideBlockQuote() {
        #expect(
            TitleSync.applying(fileName: "新題.md", to: "> # 引用\n")
                == "# 新題\n\n> # 引用\n"
        )
    }

    @Test("#見出し（空白なし）は見出しではない")
    func ignoresHashWithoutSpace() {
        // `#hashtag` は CommonMark では見出しにならない。挿し込む側に回る。
        #expect(
            TitleSync.applying(fileName: "新題.md", to: "#hashtag\n")
                == "# 新題\n\n#hashtag\n"
        )
    }

    // MARK: - 入れないとき

    @Test("見出しにできない名前では何もしない")
    func ignoresUnusableName() {
        // 隠しファイル。`# .md` という見出しには意味が無い。
        #expect(TitleSync.applying(fileName: ".md", to: "本文\n") == nil)
        // 空白だけの名前。
        #expect(TitleSync.applying(fileName: "   .md", to: "本文\n") == nil)
    }

    @Test("2行目以降は、どの場面でも動かない")
    func neverTouchesLaterLines() {
        // 差し替えでも挿し込みでも、1行目より下は元のまま残る。
        let body = "本文1\n# 途中の見出し\n本文2\n"
        #expect(TitleSync.applying(fileName: "新題.md", to: "# 旧題\n" + body) == "# 新題\n" + body)
        #expect(TitleSync.applying(fileName: "新題.md", to: body) == "# 新題\n\n" + body)
    }

    // MARK: - 本文 → ファイル名

    @Test("見出しからファイル名を作る。拡張子は残す")
    func buildsFileNameFromHeading() {
        #expect(TitleSync.fileName(for: "# 企画\n本文\n", currentName: "旧題.md") == "企画.md")
        #expect(TitleSync.fileName(for: "# 企画\n", currentName: "旧題.markdown") == "企画.markdown")
        // 拡張子が無ければ付けない。
        #expect(TitleSync.fileName(for: "# 企画\n", currentName: "旧題") == "企画")
    }

    @Test("見出しの記法は落とす")
    func stripsMarkupFromFileName() {
        #expect(TitleSync.fileName(for: "# **企画**\n", currentName: "旧題.md") == "企画.md")
        #expect(
            TitleSync.fileName(for: "# [参考](https://example.com)\n", currentName: "旧題.md")
                == "参考.md"
        )
    }

    @Test("同じ名前になるなら改名しない")
    func ignoresUnchangedFileName() {
        #expect(TitleSync.fileName(for: "# 企画\n", currentName: "企画.md") == nil)
    }

    @Test("先頭が見出しでなければ改名しない")
    func ignoresWhenNoLeadingHeading() {
        #expect(TitleSync.fileName(for: "本文だけ。\n", currentName: "旧題.md") == nil)
        #expect(TitleSync.fileName(for: "## 節\n", currentName: "旧題.md") == nil)
        #expect(TitleSync.fileName(for: "```sh\n# コメント\n```\n", currentName: "旧題.md") == nil)
        #expect(TitleSync.fileName(for: "> # 引用\n", currentName: "旧題.md") == nil)
        #expect(TitleSync.fileName(for: "", currentName: "旧題.md") == nil)
    }

    @Test("見出しが空なら改名しない")
    func ignoresEmptyHeading() {
        #expect(TitleSync.fileName(for: "#\n本文\n", currentName: "旧題.md") == nil)
        #expect(TitleSync.fileName(for: "#   \n本文\n", currentName: "旧題.md") == nil)
    }

    @Test("ファイル名に使えない文字が入っていたら改名しない")
    func ignoresUnusableCharacters() {
        // `/` はパスの区切り。`:` は Finder が `/` と入れ替えて見せる。
        // 置き換えると利用者の意図と違う名前になるので、何もしない。
        #expect(TitleSync.fileName(for: "# 2026/08/18 の記録\n", currentName: "旧題.md") == nil)
        #expect(TitleSync.fileName(for: "# 12:34 の記録\n", currentName: "旧題.md") == nil)
    }

    @Test("隠しファイルになる名前は作らない")
    func ignoresHiddenFileName() {
        #expect(TitleSync.fileName(for: "# .zshrc の話\n", currentName: "旧題.md") == nil)
    }

    @Test("長すぎる名前は作らない")
    func ignoresTooLongFileName() {
        // ファイル名の上限は 255 バイト。日本語は1文字3バイト。
        let long = String(repeating: "あ", count: 90)
        #expect(TitleSync.fileName(for: "# \(long)\n", currentName: "旧題.md") == nil)
        let fits = String(repeating: "あ", count: 80)
        #expect(TitleSync.fileName(for: "# \(fits)\n", currentName: "旧題.md") == "\(fits).md")
    }
}
