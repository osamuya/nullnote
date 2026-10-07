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
    /// **確かめられたときだけ true にする。** 逃がし文字（`\*`）や文字参照（`&amp;`）は
    /// 本文と字数が違うので false になり、範囲を丸ごと対応させる。
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
