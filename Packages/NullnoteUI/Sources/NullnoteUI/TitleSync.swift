import Foundation
import MarkdownCore

/// ファイル名と、本文の先頭の見出しを揃える。
///
/// 向きは2つある。どちらも**判断するだけ**で、実行は呼ぶ側（`DocumentView`）。
///
/// | 向き | 関数 | いつ |
/// |---|---|---|
/// | ファイル名 → 本文 | `applying(fileName:to:)` | 改名に気づいたとき |
/// | 本文 → ファイル名 | `fileName(for:currentName:)` | 保存したとき |
///
/// **副作用を持たない。** ファイルも書類も触らない。差し替えたあとの本文や、
/// 付け直すべき名前を返すだけ。`ExternalChangeResolver` と同じ作りにして、
/// 判断だけをテストで縛る。
///
/// ## 「先頭の見出し」は1行目だけを見る
///
/// 文書のどこかにある最初の見出しではなく、**空行を除いた最初の行**だけを見る。
/// 途中の見出しまで拾うと、本文を書き進めたあとの改名で、
/// 遠く離れた行が黙って書き換わる。1行目に限れば、何が起きるか読める。
///
/// 行の解釈は `MarkdownTokenizer` に任せる。自前で `#` を数えると、
/// コードブロックの中（```` ``` ````…`# これは見出しではない`）や
/// 引用の中（`> # 見出し`）を取り違える。
public enum TitleSync {

    /// ファイル名から見出しの文字列を作る。拡張子は落とす。
    ///
    /// `メモ.md` → `メモ`、`v1.2 案.md` → `v1.2 案`、拡張子が無ければそのまま。
    public static func title(fromFileName fileName: String) -> String {
        (fileName as NSString).deletingPathExtension
            .trimmingCharacters(in: .whitespaces)
    }

    /// ファイル名に合わせて先頭の見出しを直した本文を返す。**直すところが無ければ nil。**
    ///
    /// - 先頭が `#` の見出し → 見出しの本文だけを差し替える（`#` と閉じの `#` は残す）
    /// - そうでなければ → 先頭に `# タイトル` を挿し込む
    ///
    /// 名前が変わっていない移動（別のフォルダへ移しただけ）では、
    /// 見出しの文字列が同じになるので nil が返り、本文は触られない。
    public static func applying(fileName: String, to source: String) -> String? {
        // 隠しファイル（`.md` のように `.` で始まる名前）は見出しにしない。
        // `NSString` はこれを「拡張子の無い名前」と読むので、落とす前に外す。
        guard !fileName.hasPrefix(".") else { return nil }

        let title = title(fromFileName: fileName)
        // 空白だけの名前などで空になったら、何も入れない。
        guard !title.isEmpty else { return nil }

        guard let line = firstContentLine(in: source) else {
            return inserting(title, into: source)
        }

        let tokens = MarkdownTokenizer().tokenizeLine(source, range: line, stateBefore: .blank)
        guard let marker = titleMarker(in: tokens, source: source, line: line) else {
            return inserting(title, into: source)
        }

        var result = source
        if let text = headingText(in: tokens) {
            // 比べるのは**記法を落とした見出し**。`# **企画**` を `企画.md` に
            // 合わせるとき、太字を剥がすためだけに書き換えない。
            guard MarkdownPlainText.text(of: text, in: source, tokens: tokens.tokens) != title else {
                return nil
            }
            result.replaceSubrange(text, with: title)
        } else {
            // `#` だけ、`# ` だけの行。記法文字のうしろを丸ごと書き直す。
            result.replaceSubrange(marker.upperBound..<line.upperBound, with: " " + title)
        }
        return result
    }

    // MARK: - 本文 → ファイル名

    /// 先頭の見出しに合わせたファイル名を返す。**変える必要が無ければ nil。**
    ///
    /// 拡張子は元のまま残す。`# 企画` ＋ `旧題.md` → `企画.md`。
    ///
    /// **返さない（＝改名しない）場面をはっきりさせておく。**
    /// 改名はディスクを触る操作なので、迷ったら何もしない側に倒す。
    ///
    /// - 先頭が `#` の見出しでない … 合わせる元が無い
    /// - 見出しが空、または空白だけ
    /// - ファイル名に使えない文字（`/` `:`）が入っている … 置き換えると別の名前になる
    /// - `.` で始まる名前になる … 隠しファイルにしてしまう
    /// - 255 バイトを超える … ファイルシステムが受け付けない
    public static func fileName(for source: String, currentName: String) -> String? {
        guard let line = firstContentLine(in: source) else { return nil }
        let tokens = MarkdownTokenizer().tokenizeLine(source, range: line, stateBefore: .blank)
        guard titleMarker(in: tokens, source: source, line: line) != nil,
              let text = headingText(in: tokens)
        else { return nil }

        let base = MarkdownPlainText.text(of: text, in: source, tokens: tokens.tokens)
        guard !base.isEmpty, !base.hasPrefix("."), base.allSatisfy({ $0 != "/" && $0 != ":" })
        else { return nil }

        let ext = (currentName as NSString).pathExtension
        let candidate = ext.isEmpty ? base : "\(base).\(ext)"
        guard candidate != currentName, candidate.utf8.count <= 255 else { return nil }
        return candidate
    }

    // MARK: - 走査

    /// 空行を除いた最初の行。全部が空なら nil。
    ///
    /// 改行の切り方は `MarkdownCore` の行分割と合わせる（`isNewline` は CRLF も1つと数える）。
    private static func firstContentLine(in source: String) -> Range<String.Index>? {
        var start = source.startIndex
        while start < source.endIndex {
            var end = start
            while end < source.endIndex, !source[end].isNewline {
                end = source.index(after: end)
            }
            if !source[start..<end].allSatisfy(\.isWhitespace) { return start..<end }
            start = end < source.endIndex ? source.index(after: end) : end
        }
        return nil
    }

    /// その行が `#`（レベル1）の見出しなら、`#` の範囲を返す。
    ///
    /// 閉じの `###` も同じ種類のトークンになるが、開く側が先に並ぶので最初の1つでよい。
    private static func titleMarker(
        in tokens: MarkdownLineTokens,
        source: String,
        line: Range<String.Index>
    ) -> Range<String.Index>? {
        for token in tokens.tokens {
            guard case .marker(.heading) = token.kind else { continue }
            // 引用の中（`> # 見出し`）は先頭の見出しではない。行の頭から始まるものだけ。
            guard source[line.lowerBound..<token.range.lowerBound].allSatisfy(\.isWhitespace) else {
                return nil
            }
            // `##` 以下は「先頭の # のタイトル」ではない。挿し込む側に回す。
            guard source[token.range].count == 1 else { return nil }
            return token.range
        }
        return nil
    }

    /// 見出しの本文。`#` だけの行では出てこない。
    private static func headingText(in tokens: MarkdownLineTokens) -> Range<String.Index>? {
        for token in tokens.tokens {
            if case .heading = token.kind { return token.range }
        }
        return nil
    }

    /// 先頭に見出しを挿し込む。すでに空行で始まっているなら、空行を増やさない。
    private static func inserting(_ title: String, into source: String) -> String {
        guard let first = source.first else { return "# \(title)\n" }
        return first.isNewline ? "# \(title)\n" + source : "# \(title)\n\n" + source
    }
}
