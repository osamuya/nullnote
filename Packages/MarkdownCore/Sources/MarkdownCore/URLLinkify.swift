import Foundation

/// 打ち終えた URL を `[URL](URL)` に変える。
///
/// **副作用を持たない。** どこを何に書き換えるかだけを決める。
/// 実際に本文を触るのは呼ぶ側（`FocusReportingTextView`）。
///
/// ## 決めたこと（2026-08-31）
///
/// | | |
/// |---|---|
/// | いつ変えるか | **空白・改行を打った時点**と、**貼り付けたとき** |
/// | 対象 | `https://` `http://` で始まり、**ホストの形をしているもの**。`www.` は変えない |
///
/// `www.` を外したのは、`](www.example.com)` がブラウザで**相対パス**として
/// 読まれるため。リンク先が壊れる。プレビューの自動リンク（裸の URL）は
/// `www.` も拾うが、あちらは表示のときにスキームを補える。
///
/// URL は終わりの印を持たないので、打っている最中には確定できない。
/// **区切りを打った時点で、その手前を見る。**
public enum URLLinkify {

    /// 書き換えの中身。
    public struct Replacement: Equatable {
        /// 置き換える範囲（UTF-16、行頭からの位置）。
        public let range: Range<Int>
        /// 置き換えたあとの文字列。
        public let text: String
    }

    /// カーソルの手前にある URL を探す。
    ///
    /// - Parameters:
    ///   - line: いまカーソルがある行。**改行文字を含まない。**
    ///   - caretUTF16Offset: 行頭から数えたカーソルの位置。**この手前を見る。**
    public static func replacement(line: String, caretUTF16Offset caret: Int) -> Replacement? {
        guard caret > 0, caret <= line.utf16.count else { return nil }
        let head = String(decoding: Array(line.utf16)[0..<caret], as: UTF16.self)

        // 直前の空白より後ろが、URL の候補。
        var start = head.endIndex
        while start > head.startIndex {
            let previous = head.index(before: start)
            if head[previous].isWhitespace { break }
            start = previous
        }
        let candidate = String(head[start..<head.endIndex])

        guard isLinkable(candidate), allowsLinkify(line: line, caretUTF16Offset: caret)
        else { return nil }

        let startOffset = caret - candidate.utf16.count
        return Replacement(
            range: startOffset..<caret,
            text: "[\(candidate)](\(candidate))"
        )
    }

    /// 貼り付けた文字列が、そのままリンクにできる URL か。
    ///
    /// **前後に何も付いていないときだけ。** 文章ごと貼ったときに囲むと邪魔になる。
    /// **貼る先が括弧の中かどうかは、呼ぶ側が `allowsLinkify` で確かめる。**
    public static func linkify(pasted text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed == text, isLinkable(trimmed) else { return nil }
        return "[\(trimmed)](\(trimmed))"
    }

    /// リンクにしてよい形か。
    ///
    /// **ドットの有無では判定しない。** ドットの無いホスト名は実際にある。
    ///
    /// | 形 | どこで見るか |
    /// |---|---|
    /// | `http://localhost:6080/` | 手元の開発 |
    /// | `http://api:8000/` | Docker Compose のサービス名 |
    /// | `http://wiki/` | 社内の単一ラベルのホスト名 |
    ///
    /// かわりに**ホストとして成立する形か**を見る。文字数でも判定しない
    /// （`http://sum.com/` のように短いものがある）。
    ///
    /// プレビューの自動リンク（`InlineScanner.urlAutolink`）はドットを要求するが、
    /// **あちらは裸の語を推測で拾う**ので条件が違ってよい。
    /// こちらは利用者が `http://` と明示して打っている。
    private static func isLinkable(_ candidate: String) -> Bool {
        guard let scheme = ["https://", "http://"].first(where: { candidate.hasPrefix($0) })
        else { return false }
        // 角括弧と丸括弧を含むものは触らない。
        //
        // **`[…](…)` に入れると記法が壊れる。** 既にリンクの一部である場合もあるし、
        // IPv6 のリテラル（`http://[::1]:8080/`）もここで外れる。
        // エスケープすれば通せるが（`\[` `\]`）、見た目が汚れる割に出番が無い。
        guard !candidate.contains("["), !candidate.contains("]"),
              !candidate.contains("("), !candidate.contains(")")
        else { return false }
        return isHost(hostPart(of: candidate.dropFirst(scheme.count)))
    }

    /// スキームの後ろから、最初の `/` `?` `#` までを取り、`:ポート` を外す。
    private static func hostPart(of rest: Substring) -> Substring {
        rest.prefix { $0 != "/" && $0 != "?" && $0 != "#" }.prefix { $0 != ":" }
    }

    /// ホスト名として成立する形か。
    ///
    /// **英数字・ハイフン・ドットだけ。ハイフンやドットで始まり終わらない。**
    /// ドットの有無は問わない（`localhost` `api` `wiki` を通すため）。
    private static func isHost(_ host: Substring) -> Bool {
        guard !host.isEmpty else { return false }
        guard host.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." })
        else { return false }
        guard let first = host.first, let last = host.last else { return false }
        return first.isLetter || first.isNumber ? (last.isLetter || last.isNumber) : false
    }

    /// そこでリンクを作ってよいか。
    ///
    /// **閉じていない `(` や `<` の中では作らない。**
    /// `[](…)` の丸括弧はリンクの行き先で、そこに `[URL](URL)` を入れると
    /// 二重になって記法が壊れる（実測。2026-08-31）。
    /// `<https://…>` の山括弧も同じ。
    ///
    /// 文中の丸括弧（`(詳しくは https://… )`）でも作らなくなるが、
    /// **括弧の中でだけ囲みたい場面が思いつかない**ので、まとめて止めている。
    ///
    /// 貼り付けと打鍵の両方から通す。**片方だけに入れると、もう片方から漏れる。**
    public static func allowsLinkify(line: String, caretUTF16Offset caret: Int) -> Bool {
        guard caret >= 0, caret <= line.utf16.count else { return false }
        let head = String(decoding: Array(line.utf16)[0..<caret], as: UTF16.self)

        var depth = 0
        for character in head {
            switch character {
            case "(", "<": depth += 1
            case ")", ">": depth = max(0, depth - 1)
            default: break
            }
        }
        return depth == 0
    }
}
