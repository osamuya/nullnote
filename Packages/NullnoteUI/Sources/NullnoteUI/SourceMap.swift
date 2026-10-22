import Foundation

// 本文とプレビューの文字の対応（#M0045）。
//
// プレビューの文字は記法の記号を落としてあり、インラインコードの頭には
// 幅ゼロの文字も足してあるので、位置がそのままでは合わない。
// プレビューを組むときに、ひと続きの文字ごとに「本文のどこから来たか」を持たせ、
// 選択を相手側に写すときはそれを引く。

/// プレビューのひと続きの文字が、本文のどこから来たか。
///
/// 位置は本文全体の UTF-16 の位置（`NSTextView` と同じ数え方）。
struct SourceSpan: Hashable, Sendable {
    /// 本文での始まり。
    let start: Int
    /// 本文での終わり（含まない）。
    let end: Int
    /// プレビューの文字が、本文の `start` から1文字ずつそのまま並んでいるか。
    ///
    /// **確かめられたときだけ true にする。** 逃がし文字（`\*`）や文字参照（`&amp;`）のように
    /// 本文と違うところは false になり、範囲を丸ごと対応させる（`SourceAlignment`）。
    let isExact: Bool
}

/// `AttributedString` に載せる、本文の位置。
enum PreviewSourceAttribute: AttributedStringKey {
    typealias Value = SourceSpan
    static let name = "NullnotePreviewSource"
}

extension NSAttributedString.Key {
    /// `NSAttributedString` に載せる、本文の位置。中身は `PreviewSourceRun`。
    static let previewSource = NSAttributedString.Key("NullnotePreviewSource")
}

/// `NSAttributedString` に載せる値。
///
/// `extra` は頭に足した、本文に無い文字の数（インラインコードの幅ゼロの文字）。
final class PreviewSourceRun: NSObject {
    let span: SourceSpan
    let extra: Int

    init(span: SourceSpan, extra: Int) {
        self.span = span
        self.extra = extra
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? PreviewSourceRun else { return false }
        return span == other.span && extra == other.extra
    }

    override var hash: Int { span.hashValue ^ extra }
}

// MARK: - 本文の行と列を位置に直す

/// swift-markdown の行と列を、本文全体の UTF-16 の位置に直す。
///
/// 列は **UTF-8 のバイト数**で数えられている（cmark の数え方）。
/// 日本語は1文字3バイトなので、そのまま使うとずれる。
struct SourcePositionConverter {

    private let lines: [Substring]
    /// 各行の先頭の位置（UTF-16）。
    private let lineStarts: [Int]

    init(_ source: String) {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        var starts: [Int] = []
        starts.reserveCapacity(lines.count)
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += line.utf16.count + 1
        }
        self.lines = lines
        self.lineStarts = starts
    }

    /// - Parameters:
    ///   - line: 本文の行。1 始まり。
    ///   - column: その行の列。1 始まり、UTF-8 のバイト数。
    func offset(line: Int, column: Int) -> Int? {
        guard line >= 1, line <= lines.count, column >= 1 else { return nil }
        let text = lines[line - 1]
        let bytes = column - 1
        let index = text.utf8.index(text.startIndex, offsetBy: bytes, limitedBy: text.endIndex)
            ?? text.endIndex
        return lineStarts[line - 1] + text[..<index].utf16.count
    }
}

// MARK: - 本文とプレビューの文字を突き合わせる

/// 本文の範囲とプレビューの文字を突き合わせ、合うところと合わないところに分ける。
///
/// 1か所でも違うと範囲を丸ごと対応させていたので、長い段落では2文字選んでも段落全体に
/// 色が付いた（#010）。違いの出どころは、改行の記法の行末の空白（本文の範囲には入り、
/// プレビューの文字には無い）、逃がし文字（`\*`）、`...` が `…` になるところなど。
/// 違うところだけを丸ごと対応させ、前後は1文字ずつ対応させる。
enum SourceAlignment {

    struct Piece: Equatable {
        /// プレビューに出す文字。
        let rendered: String
        let span: SourceSpan
    }

    /// 合わなくなったところから、先で合い直すところを探す幅（Unicode スカラー）。
    private static let searchWidth = 8
    /// 合い直したと見なすのに、続けて一致していなければならない数。
    private static let resyncLength = 3

    /// - Parameters:
    ///   - source: 本文のその範囲の文字。
    ///   - start: `source` の頭の、本文全体での位置（UTF-16）。
    ///   - rendered: プレビューに出す文字。
    /// - Returns: `rendered` を頭から分けたもの。つなげると `rendered` に戻る。
    static func pieces(source: String, start: Int, rendered: String) -> [Piece] {
        let src = Array(source.unicodeScalars)
        let out = Array(rendered.unicodeScalars)
        // 各スカラーの頭の、本文全体での位置。
        var offsets: [Int] = []
        offsets.reserveCapacity(src.count + 1)
        var offset = start
        for scalar in src {
            offsets.append(offset)
            offset += scalar.utf16.count
        }
        offsets.append(offset)

        var pieces: [Piece] = []
        func add(_ out: ArraySlice<Unicode.Scalar>, from low: Int, to high: Int, exact: Bool) {
            guard !out.isEmpty else { return }
            var text = String.UnicodeScalarView()
            text.append(contentsOf: out)
            pieces.append(Piece(
                rendered: String(text),
                span: SourceSpan(start: offsets[low], end: offsets[high], isExact: exact)
            ))
        }

        var i = 0, j = 0
        while j < out.count {
            // 一致する並びを伸ばす。
            let i0 = i, j0 = j
            while i < src.count, j < out.count, src[i] == out[j] {
                i += 1
                j += 1
            }
            add(out[j0..<j], from: i0, to: i, exact: true)
            guard j < out.count else { break }

            // 合わないところ。先で合い直すところを、飛ばす数の少ない順に探す。
            if let (skipSource, skipRendered) = resync(src, i, out, j) {
                add(out[j..<(j + skipRendered)], from: i, to: i + skipSource, exact: false)
                i += skipSource
                j += skipRendered
            } else {
                // 見つからなければ、残りを丸ごと。
                add(out[j...], from: i, to: src.count, exact: false)
                break
            }
        }
        return pieces
    }

    private static func resync(
        _ src: [Unicode.Scalar], _ i: Int, _ out: [Unicode.Scalar], _ j: Int
    ) -> (Int, Int)? {
        for total in 1...(searchWidth * 2) {
            for skipSource in 0...min(total, searchWidth) {
                let skipRendered = total - skipSource
                guard skipRendered <= searchWidth,
                      i + skipSource <= src.count, j + skipRendered <= out.count
                else { continue }
                if matches(src, i + skipSource, out, j + skipRendered) {
                    return (skipSource, skipRendered)
                }
            }
        }
        return nil
    }

    /// その位置から先が続けて一致するか。両方が同時に終わるときも一致と見なす。
    private static func matches(_ src: [Unicode.Scalar], _ i: Int, _ out: [Unicode.Scalar], _ j: Int) -> Bool {
        var k = 0
        while k < resyncLength {
            let a = i + k, b = j + k
            if a == src.count || b == out.count { return a == src.count && b == out.count }
            if src[a] != out[b] { return false }
            k += 1
        }
        return true
    }
}

// MARK: - 選択を相手側に写す

/// プレビューの1つのテキストビューについての対応表。
struct PreviewSourceIndex: Equatable {

    struct Run: Equatable {
        /// テキストビューの中の範囲。
        let range: NSRange
        let span: SourceSpan
        let extra: Int
    }

    let runs: [Run]

    init(runs: [Run]) {
        self.runs = runs
    }

    init(_ string: NSAttributedString) {
        var runs: [Run] = []
        string.enumerateAttribute(
            .previewSource, in: NSRange(location: 0, length: string.length)
        ) { value, range, _ in
            guard let run = value as? PreviewSourceRun else { return }
            runs.append(Run(range: range, span: run.span, extra: run.extra))
        }
        self.runs = runs
    }

    /// 本文のどの範囲を受け持っているか。関係の無い範囲を早く外すために使う。
    var sourceBounds: NSRange? {
        guard let low = runs.map(\.span.start).min(), let high = runs.map(\.span.end).max() else {
            return nil
        }
        return NSRange(location: low, length: high - low)
    }

    /// プレビューで選んだ範囲を、本文の範囲に直す。
    ///
    /// 途中に記号を挟んでいても、本文では始まりから終わりまで一続きにする。
    func sourceRange(forPreview range: NSRange) -> NSRange? {
        guard range.length > 0 else { return nil }
        let first = runs.first { NSIntersectionRange($0.range, range).length > 0 }
        let last = runs.last { NSIntersectionRange($0.range, range).length > 0 }
        guard let first, let last else { return nil }

        let start = first.sourceOffset(at: max(range.location, first.range.location), edge: .start)
        let end = last.sourceOffset(at: min(NSMaxRange(range), NSMaxRange(last.range)), edge: .end)
        guard end > start else { return nil }
        return NSRange(location: start, length: end - start)
    }

    /// 本文の範囲を、このテキストビューの中の範囲に直す。重ならなければ空。
    func previewRanges(forSource sources: [NSRange]) -> [NSRange] {
        var result: [NSRange] = []
        for source in sources where source.length > 0 {
            for run in runs {
                guard let range = run.previewRange(overlapping: source) else { continue }
                // 隣り合う並びは1つにまとめる（塗りの継ぎ目を出さない）。
                if let previous = result.last, NSMaxRange(previous) == range.location {
                    result[result.count - 1] = NSUnionRange(previous, range)
                } else {
                    result.append(range)
                }
            }
        }
        return result
    }
}

private extension PreviewSourceIndex.Run {

    enum Edge { case start, end }

    /// テキストビューの中の位置を、本文の位置に直す。
    func sourceOffset(at location: Int, edge: Edge) -> Int {
        guard span.isExact else { return edge == .start ? span.start : span.end }
        // 頭に足した文字は、本文の始まりに寄せる。
        let inside = max(0, location - range.location - extra)
        return min(span.start + inside, span.end)
    }

    /// 本文の範囲と重なるところを、テキストビューの中の範囲で返す。
    func previewRange(overlapping source: NSRange) -> NSRange? {
        let low = max(source.location, span.start)
        let high = min(NSMaxRange(source), span.end)
        guard high > low else { return nil }
        guard span.isExact else { return range }

        let start = range.location + extra + (low - span.start)
        let end = range.location + extra + (high - span.start)
        let clipped = NSIntersectionRange(
            NSRange(location: start, length: end - start), range
        )
        return clipped.length > 0 ? clipped : nil
    }
}
