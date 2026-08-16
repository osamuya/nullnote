import Foundation

/// 同じ語をいくつも選び、まとめて書き換えるための計算。
///
/// **副作用を持たない。** テキストビューにも書類にも触らない。
/// 「どこを選ぶか」「打ったらどうなるか」だけをここに集めて、テストで縛る。
///
/// ## `NSTextView` は見せてくれるだけ
///
/// 複数の範囲を選ぶこと自体はできる（ハイライトも出る）。
/// **ただし打っても最初の1つにしか効かない。** 削除も同じ。実測で確かめた。
/// 書き換えは自分で全範囲に適用する必要がある。
public enum MultiSelection {

    // MARK: - 選ぶ

    /// その位置にある語の範囲。語の上に無ければ `nil`。
    ///
    /// **文字種の変わり目で切る。** 日本語には語の区切りが無いので、
    /// 「文字が続くかたまり」を語にすると `。` まで丸ごと1語になってしまう
    /// （「ナイフを刺し入れ血を抜く」で1語）。
    /// 片仮名・平仮名・漢字・英数字が切り替わったところを境目にする。
    ///
    /// 形態素解析ではないので完全ではない（「お刺身」は「お」と「刺身」に割れる）。
    /// それでも「ナイフ」「猪」のような語は素直に取れる。
    public static func wordRange(at location: Int, in text: String) -> NSRange? {
        let string = text as NSString
        guard location >= 0, location <= string.length else { return nil }

        func kind(at index: Int) -> ScriptKind? {
            guard index >= 0, index < string.length else { return nil }
            return ScriptKind(utf16: string.character(at: index))
        }

        // カーソルが語の直後にある場合も拾う（打ち終えた直後に押すことが多い）。
        var start = location
        if kind(at: start) == nil, kind(at: start - 1) != nil { start -= 1 }
        guard let target = kind(at: start) else { return nil }

        var end = start
        while kind(at: start - 1) == target { start -= 1 }
        while kind(at: end + 1) == target { end += 1 }
        return NSRange(location: start, length: end - start + 1)
    }

    /// 語を切る単位。同じ種類が続くあいだをひとかたまりと見る。
    enum ScriptKind: Equatable {
        /// 英数字と `_`。識別子はここ。
        case latin
        case hiragana
        /// 片仮名と長音符（`ー`）。`コーヒー` を割らないため。
        case katakana
        case kanji

        init?(utf16 unit: unichar) {
            guard let scalar = Unicode.Scalar(unit) else { return nil }
            let character = Character(scalar)
            let value = scalar.value

            switch value {
            case 0x3041...0x309F:                       // 平仮名
                self = .hiragana
            case 0x30A0...0x30FF, 0xFF66...0xFF9F:      // 片仮名（長音符・半角も含む）
                self = .katakana
            case 0x4E00...0x9FFF, 0x3005, 0x3007:       // 漢字と々〇
                self = .kanji
            default:
                guard character.isLetter || character.isNumber || character == "_" else { return nil }
                self = .latin
            }
        }
    }

    /// すでに選んである範囲の**後ろ**から、次に同じ語が出てくるところ。
    ///
    /// 末尾まで行ったら先頭へ回る。すべて選び終えていれば `nil`。
    public static func nextOccurrence(
        of word: String, after selected: [NSRange], in text: String
    ) -> NSRange? {
        guard !word.isEmpty else { return nil }
        let string = text as NSString
        let searchStart = selected.map { $0.location + $0.length }.max() ?? 0

        func find(from location: Int, to end: Int) -> NSRange? {
            guard location < end else { return nil }
            let found = string.range(
                of: word, options: [], range: NSRange(location: location, length: end - location)
            )
            return found.location == NSNotFound ? nil : found
        }

        // 後ろを探し、無ければ先頭へ回る。
        let candidate = find(from: searchStart, to: string.length) ?? find(from: 0, to: searchStart)
        guard let candidate else { return nil }
        // 一周して同じところに戻ってきたら、もう増やせない。
        guard !selected.contains(candidate) else { return nil }
        return candidate
    }

    /// 文書に出てくる同じ語すべて。重なりは作らない。
    public static func allOccurrences(of word: String, in text: String) -> [NSRange] {
        DocumentSearch.matches(of: word, in: text, caseSensitive: true)
    }

    // MARK: - 消す

    /// 消す範囲を決める。
    ///
    /// - 選んであるところは、その範囲ごと。
    /// - カーソルだけのところは、その手前（`forward` なら後ろ）の1文字。
    ///
    /// 1文字は UTF-16 の1単位ではない。絵文字も濁点付きの仮名も、
    /// 見た目のひとかたまりで消す。半分だけ消すと壊れた文字が残る。
    ///
    /// 消すものが無いカーソル（本文の先頭で手前を消そうとした）は落とす。
    public static func deletions(
        for ranges: [NSRange], forward: Bool, in text: String
    ) -> [NSRange] {
        let string = text as NSString
        var result: [NSRange] = []

        for range in ranges.sorted(by: { $0.location < $1.location }) {
            guard range.length == 0 else {
                result.append(range)
                continue
            }
            if forward {
                guard range.location < string.length else { continue }
                let unit = string.rangeOfComposedCharacterSequence(at: range.location)
                // 端はカーソルに合わせる。隣り合ったカーソル同士が食い合わないように。
                result.append(NSRange(
                    location: range.location,
                    length: unit.location + unit.length - range.location
                ))
            } else {
                guard range.location > 0, range.location <= string.length else { continue }
                let unit = string.rangeOfComposedCharacterSequence(at: range.location - 1)
                result.append(NSRange(
                    location: unit.location, length: range.location - unit.location
                ))
            }
        }
        return result
    }

    // MARK: - 選び直す

    /// カーソルをそろえて1文字ぶん動かす。
    ///
    /// 選んであるところは、**まず端に畳むだけ**で動かさない。矢印キーの決まりごとで、
    /// 「→ なら後ろの端へ、← なら前の端へ」。もう一度押して初めて動く。
    ///
    /// 動いた先が重なったら1つにまとめる。同じ場所を二度書き換えると文字が増える。
    public static func moving(_ ranges: [NSRange], forward: Bool, in text: String) -> [NSRange] {
        let string = text as NSString
        var result: [NSRange] = []

        func moved(_ range: NSRange) -> Int {
            // 選んであるなら、動かさずに端へ畳む。
            if range.length > 0 { return forward ? range.location + range.length : range.location }
            if forward {
                guard range.location < string.length else { return range.location }
                let unit = string.rangeOfComposedCharacterSequence(at: range.location)
                return unit.location + unit.length
            }
            guard range.location > 0 else { return 0 }
            return string.rangeOfComposedCharacterSequence(at: range.location - 1).location
        }

        for range in ranges.sorted(by: { $0.location < $1.location }) {
            let caret = NSRange(location: moved(range), length: 0)
            if result.last != caret { result.append(caret) }
        }
        return result
    }

    /// 選ぶ範囲を1文字ぶん伸ばす（`forward`）、または縮める。
    ///
    /// **始点は動かさない。** 語を選んだところから伸ばす道具なので、
    /// 後ろの端だけを動かすほうが読みやすい。
    /// 伸ばせない・縮められない範囲はそのまま返す。
    public static func extending(
        _ ranges: [NSRange], forward: Bool, in text: String
    ) -> [NSRange] {
        let string = text as NSString
        return ranges.map { range in
            let end = range.location + range.length
            if forward {
                guard end < string.length else { return range }
                let unit = string.rangeOfComposedCharacterSequence(at: end)
                return NSRange(
                    location: range.location, length: unit.location + unit.length - range.location
                )
            } else {
                guard range.length > 0, end <= string.length else { return range }
                let unit = string.rangeOfComposedCharacterSequence(at: end - 1)
                return NSRange(
                    location: range.location, length: max(0, unit.location - range.location)
                )
            }
        }
    }

    // MARK: - 書き換える

    /// 選んである範囲すべてを `replacement` に置き換えた結果。
    ///
    /// - Returns: 置き換えたあとの本文と、置き換えた各所の**後ろに来るカーソル**。
    ///
    /// 後ろから順に置き換える。前から置き換えると、2つ目以降の位置がずれる。
    public static func replacing(
        _ ranges: [NSRange], with replacement: String, in text: String
    ) -> (text: String, selections: [NSRange]) {
        let sorted = ranges.sorted { $0.location < $1.location }
        guard !sorted.isEmpty else { return (text, []) }

        let result = NSMutableString(string: text)
        for range in sorted.reversed() {
            guard range.location >= 0, range.location + range.length <= result.length else { continue }
            result.replaceCharacters(in: range, with: replacement)
        }

        return (result as String, carets(after: sorted, replacedWith: replacement))
    }

    /// 置き換えたあとにカーソルが来る場所。置き換えた各所の**直後**。
    ///
    /// 前から順に、置き換えたぶんだけ後ろがずれていく。
    /// 打ち込みを続けられるよう、範囲ではなく長さ0のカーソルにする。
    public static func carets(after ranges: [NSRange], replacedWith replacement: String) -> [NSRange] {
        let sorted = ranges.sorted { $0.location < $1.location }
        let inserted = (replacement as NSString).length
        var result: [NSRange] = []
        var shift = 0
        for range in sorted {
            result.append(NSRange(location: range.location + shift + inserted, length: 0))
            shift += inserted - range.length
        }
        return result
    }
}
