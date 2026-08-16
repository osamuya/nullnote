import Foundation
import Testing
@testable import NullnoteUI

/// 同じ語を選んで、まとめて書き換える計算。
///
/// **書き換えは後ろから当てる。** 前から当てると2つ目以降の位置がずれ、
/// 見当違いのところを壊す。ここを重点的に縛る。
@Suite("同じ語の複数選択")
struct MultiSelectionTests {

    // MARK: - 語を拾う

    @Test("カーソルのある語を拾う")
    func wordUnderCursor() {
        let text = "cat dog bird"
        #expect(MultiSelection.wordRange(at: 0, in: text) == NSRange(location: 0, length: 3))
        #expect(MultiSelection.wordRange(at: 1, in: text) == NSRange(location: 0, length: 3))
        #expect(MultiSelection.wordRange(at: 5, in: text) == NSRange(location: 4, length: 3))
    }

    @Test("語の直後でも拾う")
    func wordJustAfterCursor() {
        // 打ち終えた直後に押すことが多い。
        #expect(MultiSelection.wordRange(at: 3, in: "cat dog") == NSRange(location: 0, length: 3))
    }

    @Test("記号や下線を含む語")
    func identifiers() {
        let text = "let my_value = 1"
        #expect(MultiSelection.wordRange(at: 5, in: text) == NSRange(location: 4, length: 8))
    }

    @Test("語の上に無ければ拾わない")
    func notOnAWord() {
        #expect(MultiSelection.wordRange(at: 0, in: "   ") == nil)
        #expect(MultiSelection.wordRange(at: 0, in: "") == nil)
    }

    // MARK: - 次を探す

    @Test("次に出てくる同じ語を選ぶ")
    func findsNextOccurrence() {
        let text = "cat dog cat dog cat"
        let first = NSRange(location: 0, length: 3)
        #expect(MultiSelection.nextOccurrence(of: "cat", after: [first], in: text)
                == NSRange(location: 8, length: 3))
    }

    @Test("末尾まで行ったら先頭へ回る")
    func wrapsAround() {
        let text = "cat dog cat"
        let last = NSRange(location: 8, length: 3)
        #expect(MultiSelection.nextOccurrence(of: "cat", after: [last], in: text)
                == NSRange(location: 0, length: 3))
    }

    @Test("すべて選び終えたら、それ以上増やさない")
    func stopsWhenAllSelected() {
        let text = "cat dog cat"
        let all = [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)]
        #expect(MultiSelection.nextOccurrence(of: "cat", after: all, in: text) == nil)
    }

    @Test("大文字小文字を区別する")
    func caseSensitive() {
        // `Foo` を選んだつもりで `foo` まで書き換わると事故になる。
        let text = "Foo foo FOO Foo"
        #expect(MultiSelection.nextOccurrence(of: "Foo", after: [NSRange(location: 0, length: 3)], in: text)
                == NSRange(location: 12, length: 3))
        #expect(MultiSelection.allOccurrences(of: "Foo", in: text).count == 2)
    }

    @Test("全部を一度に選ぶ")
    func selectsAll() {
        #expect(MultiSelection.allOccurrences(of: "cat", in: "cat dog cat dog cat").count == 3)
    }

    // MARK: - 書き換える

    @Test("選んだところを全部置き換える")
    func replacesEveryRange() {
        let text = "cat dog cat dog cat"
        let ranges = MultiSelection.allOccurrences(of: "cat", in: text)
        let result = MultiSelection.replacing(ranges, with: "bird", in: text)
        #expect(result.text == "bird dog bird dog bird")
    }

    @Test("長さの違う語に置き換えても、位置がずれない")
    func handlesLengthChange() {
        // 前から当てると2つ目以降がずれる。後ろから当てる。
        let text = "a x a x a"
        let ranges = MultiSelection.allOccurrences(of: "a", in: text)
        #expect(MultiSelection.replacing(ranges, with: "LONG", in: text).text == "LONG x LONG x LONG")
        #expect(MultiSelection.replacing(ranges, with: "", in: text).text == " x  x ")
    }

    @Test("置き換えたあと、カーソルはそれぞれの後ろに来る")
    func selectionsAfterReplacement() {
        let text = "cat dog cat"
        let ranges = MultiSelection.allOccurrences(of: "cat", in: text)
        let result = MultiSelection.replacing(ranges, with: "bird", in: text)
        // "bird dog bird" → 4 と 13
        #expect(result.selections == [NSRange(location: 4, length: 0), NSRange(location: 13, length: 0)])
    }

    @Test("日本語も置き換えられる")
    func japanese() {
        let text = "猪はおいしい。猪を食べる。"
        let ranges = MultiSelection.allOccurrences(of: "猪", in: text)
        #expect(ranges.count == 2)
        #expect(MultiSelection.replacing(ranges, with: "鹿", in: text).text == "鹿はおいしい。鹿を食べる。")
    }

    @Test("範囲が空なら何もしない")
    func noRanges() {
        #expect(MultiSelection.replacing([], with: "x", in: "そのまま").text == "そのまま")
    }

    @Test("本文より後ろを指す範囲は飛ばす")
    func ignoresOutOfBounds() {
        let text = "みじかい"
        let result = MultiSelection.replacing([NSRange(location: 100, length: 5)], with: "x", in: text)
        #expect(result.text == text)
    }

    @Test("消したあとも行き先が残る")
    func caretsAfterDeleting() {
        // "cat dog cat" から cat を2つとも消すと " dog " になり、行き先は 0 と 5。
        let ranges = MultiSelection.allOccurrences(of: "cat", in: "cat dog cat")
        let carets = MultiSelection.carets(after: ranges, replacedWith: "")
        #expect(carets == [NSRange(location: 0, length: 0), NSRange(location: 5, length: 0)])
    }

    @Test("消したあとに打つと、行き先が全部ずれる")
    func caretsAfterTypingIntoEmptyCarets() {
        // 上の続き。" dog " の 0 と 5 に "鳥" を入れると "鳥 dog 鳥" で、行き先は 1 と 7。
        let carets = MultiSelection.carets(
            after: [NSRange(location: 0, length: 0), NSRange(location: 5, length: 0)],
            replacedWith: "鳥"
        )
        #expect(carets == [NSRange(location: 1, length: 0), NSRange(location: 7, length: 0)])
    }

    @Test("カーソルだけのところは、手前の1文字を消す")
    func deleteBackwardAtCarets() {
        let carets = [NSRange(location: 3, length: 0), NSRange(location: 7, length: 0)]
        let deletions = MultiSelection.deletions(for: carets, forward: false, in: "abc def ghi")
        #expect(deletions == [NSRange(location: 2, length: 1), NSRange(location: 6, length: 1)])
    }

    @Test("後ろを消すときは、その先の1文字")
    func deleteForwardAtCarets() {
        let carets = [NSRange(location: 0, length: 0), NSRange(location: 4, length: 0)]
        let deletions = MultiSelection.deletions(for: carets, forward: true, in: "abc def ghi")
        #expect(deletions == [NSRange(location: 0, length: 1), NSRange(location: 4, length: 1)])
    }

    @Test("選んであるところは、その範囲ごと消す")
    func deleteSelections() {
        let ranges = MultiSelection.allOccurrences(of: "cat", in: "cat dog cat")
        #expect(MultiSelection.deletions(for: ranges, forward: false, in: "cat dog cat") == ranges)
    }

    @Test("絵文字は半分にしない")
    func deleteKeepsCharactersWhole() {
        // 🐗 は UTF-16 で2単位。手前を消すなら両方まとめて。
        let text = "猪🐗猪"
        let deletions = MultiSelection.deletions(
            for: [NSRange(location: 3, length: 0)], forward: false, in: text
        )
        #expect(deletions == [NSRange(location: 1, length: 2)])
    }

    @Test("消すものが無いカーソルは落とす")
    func deleteAtEdges() {
        let text = "abc"
        #expect(
            MultiSelection.deletions(
                for: [NSRange(location: 0, length: 0), NSRange(location: 2, length: 0)],
                forward: false, in: text
            ) == [NSRange(location: 1, length: 1)]
        )
        #expect(
            MultiSelection.deletions(
                for: [NSRange(location: 3, length: 0)], forward: true, in: text
            ).isEmpty
        )
    }

    @Test("→ はまず端に畳むだけ。動かさない")
    func moveCollapsesSelection() {
        let ranges = [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)]
        #expect(
            MultiSelection.moving(ranges, forward: true, in: "cat dog cat")
                == [NSRange(location: 3, length: 0), NSRange(location: 11, length: 0)]
        )
        #expect(
            MultiSelection.moving(ranges, forward: false, in: "cat dog cat")
                == [NSRange(location: 0, length: 0), NSRange(location: 8, length: 0)]
        )
    }

    @Test("カーソルは全部そろって1文字ぶん動く")
    func moveCarets() {
        let carets = [NSRange(location: 3, length: 0), NSRange(location: 11, length: 0)]
        #expect(
            MultiSelection.moving(carets, forward: false, in: "cat dog cat")
                == [NSRange(location: 2, length: 0), NSRange(location: 10, length: 0)]
        )
    }

    @Test("端に着いたカーソルはそこで止まる")
    func moveStopsAtEdges() {
        #expect(
            MultiSelection.moving(
                [NSRange(location: 0, length: 0)], forward: false, in: "abc"
            ) == [NSRange(location: 0, length: 0)]
        )
        #expect(
            MultiSelection.moving(
                [NSRange(location: 3, length: 0)], forward: true, in: "abc"
            ) == [NSRange(location: 3, length: 0)]
        )
    }

    @Test("重なったカーソルは1つにまとめる")
    func moveMergesCollisions() {
        // 0 は動けず、1 は 0 へ下がる。同じ場所を二度書き換えると文字が増える。
        let carets = [NSRange(location: 0, length: 0), NSRange(location: 1, length: 0)]
        #expect(
            MultiSelection.moving(carets, forward: false, in: "abc")
                == [NSRange(location: 0, length: 0)]
        )
    }

    @Test("⇧→ で選択を1文字ぶん伸ばす")
    func extendForward() {
        let carets = [NSRange(location: 0, length: 0), NSRange(location: 8, length: 0)]
        #expect(
            MultiSelection.extending(carets, forward: true, in: "cat dog cat")
                == [NSRange(location: 0, length: 1), NSRange(location: 8, length: 1)]
        )
    }

    @Test("⇧← で縮める。始点は動かさない")
    func extendBackward() {
        let ranges = [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)]
        #expect(
            MultiSelection.extending(ranges, forward: false, in: "cat dog cat")
                == [NSRange(location: 0, length: 2), NSRange(location: 8, length: 2)]
        )
    }

    @Test("これ以上動かせない端はそのまま")
    func extendAtEdges() {
        let text = "abc"
        // 末尾からは伸ばせない。長さ0からは縮められない。
        #expect(
            MultiSelection.extending(
                [NSRange(location: 3, length: 0)], forward: true, in: text
            ) == [NSRange(location: 3, length: 0)]
        )
        #expect(
            MultiSelection.extending(
                [NSRange(location: 1, length: 0)], forward: false, in: text
            ) == [NSRange(location: 1, length: 0)]
        )
    }

    @Test("伸ばすときも絵文字は半分にしない")
    func extendKeepsCharactersWhole() {
        #expect(
            MultiSelection.extending(
                [NSRange(location: 1, length: 0)], forward: true, in: "猪🐗猪"
            ) == [NSRange(location: 1, length: 2)]
        )
    }

    @Test("並び順が前後していても行き先は正しい")
    func caretsIgnoreOrder() {
        let jumbled = [NSRange(location: 8, length: 3), NSRange(location: 0, length: 3)]
        #expect(
            MultiSelection.carets(after: jumbled, replacedWith: "bird")
                == [NSRange(location: 4, length: 0), NSRange(location: 13, length: 0)]
        )
    }
}

extension MultiSelectionTests {

    /// 回帰テスト。
    ///
    /// 「文字が続くかたまり」を語にしていたとき、日本語では `。` まで
    /// 丸ごと1語になった（「ナイフを刺し入れ血を抜く」で1語）。
    /// 同じ並びは他に無いので、⌘D を押しても増えなかった。
    @Test("日本語は文字種の変わり目で切る")
    func japaneseWordBoundaries() {
        let text = "ナイフを刺し入れ血を抜く。まだナイフがある。"

        // 片仮名の連なりだけを拾う。
        let first = MultiSelection.wordRange(at: 0, in: text)
        #expect(first == NSRange(location: 0, length: 3))
        #expect((text as NSString).substring(with: first!) == "ナイフ")

        // 2つ目も見つかって、選択が増える。
        let next = MultiSelection.nextOccurrence(of: "ナイフ", after: [first!], in: text)
        #expect(next != nil)
        #expect((text as NSString).substring(with: next!) == "ナイフ")
    }

    @Test("長音符を含む片仮名を割らない")
    func prolongedSoundMark() {
        let text = "コーヒーを飲む"
        let word = MultiSelection.wordRange(at: 1, in: text)
        #expect((text as NSString).substring(with: word!) == "コーヒー")
    }

    @Test("漢字の連なりを拾う")
    func kanjiRun() {
        let text = "山道を歩く。山道は険しい。"
        let word = MultiSelection.wordRange(at: 0, in: text)
        #expect((text as NSString).substring(with: word!) == "山道")
        #expect(MultiSelection.allOccurrences(of: "山道", in: text).count == 2)
    }

    @Test("英数字と日本語の境目で切る")
    func mixedScripts() {
        let text = "Swiftで書く"
        let word = MultiSelection.wordRange(at: 0, in: text)
        #expect((text as NSString).substring(with: word!) == "Swift")
    }

    @Test("前に語が無ければ、句読点の上では拾わない")
    func punctuation() {
        // 先頭の `。` には、拾える語が前にも上にも無い。
        #expect(MultiSelection.wordRange(at: 0, in: "。あい") == nil)
        #expect(MultiSelection.wordRange(at: 1, in: " 。 ") == nil)
    }

    @Test("語の直後の句読点の上なら、その語を拾う")
    func punctuationAfterWord() {
        // 打ち終えた直後にカーソルがある形。「あい。」の `。` の上で押す。
        let text = "あい。うえ"
        let word = MultiSelection.wordRange(at: 2, in: text)
        #expect((text as NSString).substring(with: word!) == "あい")
    }
}
