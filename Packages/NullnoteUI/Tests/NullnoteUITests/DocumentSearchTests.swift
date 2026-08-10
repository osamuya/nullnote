import Foundation
import Testing
@testable import NullnoteUI

@Suite("文書内の検索")
struct DocumentSearchTests {

    // MARK: - 一致の見つけ方

    @Test("部分一致で見つかる")
    func partialMatch() {
        let matches = DocumentSearch.matches(of: "検索", in: "全文検索の検索窓")
        #expect(matches.count == 2)
        #expect(matches[0] == NSRange(location: 2, length: 2))
        #expect(matches[1] == NSRange(location: 5, length: 2))
    }

    @Test("大文字小文字は区別しない")
    func caseInsensitive() {
        let matches = DocumentSearch.matches(of: "swift", in: "Swift と swift と SWIFT")
        #expect(matches.count == 3)
    }

    @Test("見つからなければ空")
    func noMatch() {
        #expect(DocumentSearch.matches(of: "無い語", in: "本文です").isEmpty)
    }

    @Test("検索語が空なら何も返さない")
    func emptyQuery() {
        #expect(DocumentSearch.matches(of: "", in: "本文です").isEmpty)
    }

    @Test("本文が空なら何も返さない")
    func emptySource() {
        #expect(DocumentSearch.matches(of: "語", in: "").isEmpty)
    }

    @Test("重なる一致は数えない")
    func noOverlap() {
        // "aaa" の中の "aa" は 1 件。重なりまで数えると件数が直感と合わない。
        #expect(DocumentSearch.matches(of: "aa", in: "aaa").count == 1)
        #expect(DocumentSearch.matches(of: "aa", in: "aaaa").count == 2)
    }

    @Test("改行をまたぐ語も見つかる")
    func acrossLines() {
        #expect(DocumentSearch.matches(of: "a\nb", in: "xa\nby") == [NSRange(location: 1, length: 3)])
    }

    // MARK: - 範囲は UTF-16 で数える

    @Test("絵文字より後ろの位置が UTF-16 でずれない")
    func utf16Offsets() {
        // 🙂 は UTF-16 で 2。文字数で数えると 1 ずれ、テキストビューで塗る位置が狂う。
        let source = "🙂目印"
        let matches = DocumentSearch.matches(of: "目印", in: source)
        #expect(matches == [NSRange(location: 2, length: 2)])

        // 実際に塗れる範囲であること（NSString の長さに収まる）。
        let text = source as NSString
        #expect(text.substring(with: matches[0]) == "目印")
    }

    // MARK: - 何番目を見ているか

    @Test("数え直すと先頭のヒットから始まる")
    func startsAtFirst() {
        var session = SearchSession(query: "a")
        session.refresh(in: "a b a b a")
        #expect(session.matches.count == 3)
        #expect(session.currentIndex == 0)
        #expect(session.currentRange == NSRange(location: 0, length: 1))
    }

    @Test("ヒットが無ければ何番目も無い")
    func noCurrentWithoutMatches() {
        var session = SearchSession(query: "無い語")
        session.refresh(in: "本文です")
        #expect(session.currentIndex == nil)
        #expect(session.currentRange == nil)
    }

    @Test("次へ送ると末尾から先頭へ回る")
    func wrapsForward() {
        var session = SearchSession(query: "a")
        session.refresh(in: "a b a")
        session.moveToNext()
        #expect(session.currentIndex == 1)
        session.moveToNext()
        #expect(session.currentIndex == 0)
    }

    @Test("前へ送ると先頭から末尾へ回る")
    func wrapsBackward() {
        var session = SearchSession(query: "a")
        session.refresh(in: "a b a b a")
        session.moveToPrevious()
        #expect(session.currentIndex == 2)
        session.moveToPrevious()
        #expect(session.currentIndex == 1)
    }

    @Test("ヒットが無いときに送っても壊れない")
    func moveWithoutMatches() {
        var session = SearchSession(query: "無い語")
        session.refresh(in: "本文です")
        session.moveToNext()
        session.moveToPrevious()
        #expect(session.currentIndex == nil)
    }

    // MARK: - 数え直したときに見ている場所を保つ

    @Test("語を足しても見ていた場所の近くに留まる")
    func keepsPositionWhenQueryGrows() {
        var session = SearchSession(query: "ab")
        session.refresh(in: "ab xx abc xx abcd")
        session.moveToNext()
        session.moveToNext()
        #expect(session.currentRange?.location == 13)

        // "abc" に絞っても、先頭へ戻さず同じ場所のヒットを選ぶ。
        session.query = "abc"
        session.refresh(in: "ab xx abc xx abcd")
        #expect(session.currentRange?.location == 13)
    }

    @Test("見ていた場所より後ろにヒットが無ければ末尾を選ぶ")
    func fallsBackToLastMatch() {
        var session = SearchSession(query: "b")
        session.refresh(in: "b b b")
        session.moveToPrevious()
        #expect(session.currentIndex == 2)

        // 後ろのヒットが消えても、いちばん近い（末尾の）ヒットに残る。
        session.refresh(in: "b b")
        #expect(session.currentIndex == 1)
    }

    @Test("本文からヒットが消えたら何番目も消える")
    func clearsWhenMatchesDisappear() {
        var session = SearchSession(query: "a")
        session.refresh(in: "a")
        #expect(session.currentIndex == 0)
        session.refresh(in: "本文")
        #expect(session.currentIndex == nil)
    }

    // MARK: - 画面に出す値

    @Test("件数は「何番目 / 全体」で出す")
    func countLabel() {
        var session = SearchSession(query: "a")
        session.refresh(in: "a b a b a")
        #expect(session.countLabel == "1 / 3")
        session.moveToNext()
        #expect(session.countLabel == "2 / 3")
    }

    @Test("検索語が空なら件数を出さない")
    func countLabelWhenEmpty() {
        var session = SearchSession()
        session.refresh(in: "本文です")
        // まだ何も打っていないのに「0 件」と出すと、見つからなかったように読める。
        #expect(session.countLabel.isEmpty)
    }

    @Test("見つからなかったことは言葉で伝える")
    func countLabelWithoutMatches() {
        var session = SearchSession(query: "無い語")
        session.refresh(in: "本文です")
        #expect(session.countLabel == "見つかりません")
    }

    @Test("塗る指示には全ヒットと、いま見ている添字が入る")
    func highlight() {
        var session = SearchSession(query: "a")
        session.refresh(in: "a b a")
        session.moveToNext()
        #expect(session.highlight.matches.count == 2)
        #expect(session.highlight.current == 1)
    }
}
