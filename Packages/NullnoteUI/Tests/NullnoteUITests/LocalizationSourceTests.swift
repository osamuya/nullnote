import Foundation
import Testing

/// 画面に出す日本語が、このパッケージのカタログから引かれていることを確かめる。
///
/// **付け忘れても何も起きない。** `bundle: .module` を渡さないと `Bundle.main` を見にいき、
/// 訳が見つからずに日本語のまま出る。エラーにも警告にもならない。
///
/// `swift build` は `.xcstrings` をコンパイルしないので、`swift test` では
/// 「訳が引けるか」は確かめられない。代わりに**ソースとカタログの書き方**を見る
/// （docs/12-make-multilingual.md の 3.0.1 と 8章）。
@Suite("画面の文字列の引き先")
struct LocalizationSourceTests {

    @Test("日本語の文字列は bundle: .module を通して引く")
    func japaneseLiteralsGoThroughModuleBundle() throws {
        var checked = 0
        var offenders: [String] = []
        for file in try Self.sourceFiles() {
            let text = try String(contentsOf: file, encoding: .utf8)
            let result = Self.scan(text.components(separatedBy: "\n"))
            checked += result.checked
            offenders += result.offenders.map { "\(file.lastPathComponent):\($0.line): \($0.text)" }
        }
        // 走査が空振りしていないこと。場所を取り違えると、何も見ずに通ってしまう。
        #expect(checked >= 20, "日本語の文字列を \(checked) 行しか見つけられなかった")
        #expect(offenders.isEmpty, "bundle: .module を通していない:\n\(offenders.joined(separator: "\n"))")
    }

    @Test("検査そのものが、付け忘れを見分けられる")
    func scanDistinguishesMissingBundle() {
        let result = Self.scan([
            #"Text("目次")"#,
            #"Text("目次", bundle: .module)"#,
            #"String(localized: "閉じる", bundle: .module)"#,
            #"// 目次を隠す"#,
            #"Text("https://例.jp")"#,
            #"Trace.mark("#,
            #"    "最初の描画 本文=\(count)文字 ""#,
            #")"#,
            #".help("検索語を消す")"#,
        ])
        // コメント（4行目）と足あと（6〜8行目）は見ない。
        // 文字列の中の `//` はコメントの始まりではない（5行目）。
        #expect(result.checked == 5)
        #expect(result.offenders.map(\.line) == [1, 5, 9])
    }

    /// 元の言語（ja）を書かないと、日本語のシステムでも英語が出る（3.0.1。実際に踏んだ）。
    /// 鍵が日本語なので書かなくてよさそうに見えるが、書かないと `ja.lproj` が作られない。
    @Test("カタログのすべての文字列に ja を書いてある")
    func catalogSpellsOutJapanese() throws {
        let url = Self.packageRoot.appendingPathComponent("Sources/NullnoteUI/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        let missing = catalog.strings.filter { $0.value.localizations?["ja"] == nil }.keys.sorted()
        #expect(catalog.sourceLanguage == "ja")
        #expect(catalog.strings.count >= 20, "カタログに \(catalog.strings.count) 件しか無い")
        #expect(missing.isEmpty, "ja が無い: \(missing)")
    }

    /// 足した文字列に英語が無ければ、英語の画面にそこだけ日本語が出る。
    /// 英語の値に日本語が混じっているもの（写しただけで訳し忘れたもの）も止める。
    @Test("カタログのすべての文字列に英語の訳がある")
    func catalogHasEnglish() throws {
        let url = Self.packageRoot.appendingPathComponent("Sources/NullnoteUI/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = json?["strings"] as? [String: [String: Any]] ?? [:]
        var missing: [String] = []
        var japanese: [String] = []
        for (key, entry) in strings {
            let en = (entry["localizations"] as? [String: Any])?["en"]
            let values = en.map(Self.values(in:)) ?? []
            if values.isEmpty { missing.append(key) }
            if values.contains(where: Self.containsJapanese) { japanese.append(key) }
        }
        #expect(!strings.isEmpty)
        #expect(missing.isEmpty, "英語が無い: \(missing.sorted())")
        #expect(japanese.isEmpty, "英語の値に日本語が残っている: \(japanese.sorted())")
    }

    /// `stringUnit` の `value` を、複数形の枝も含めてすべて集める。
    private static func values(in node: Any) -> [String] {
        guard let dict = node as? [String: Any] else { return [] }
        return dict.flatMap { key, value -> [String] in
            if key == "value", let text = value as? String { return [text] }
            return values(in: value)
        }
    }

    // MARK: - 走査

    struct Offender: Equatable {
        let line: Int
        let text: String
    }

    /// 日本語の文字列を含む行の数と、そのうち `bundle: .module` の無い行を返す。
    ///
    /// 構文木は作らない。**このパッケージの書き方に合わせた、行単位の粗い判定**で足りる。
    /// - コメントは見ない（`//` から後ろ。文字列の中の `//` は除く）
    /// - 足あと（`Trace.`）は訳さない。複数行にまたがるので、括弧が閉じるまで読み飛ばす
    /// - 画面の文字列は、`bundle: .module` と同じ行に収めて書く
    static func scan(_ lines: [String]) -> (checked: Int, offenders: [Offender]) {
        var checked = 0
        var offenders: [Offender] = []
        var traceDepth = 0
        for (index, line) in lines.enumerated() {
            let code = stripComment(line)
            if traceDepth > 0 {
                traceDepth += parenBalance(code)
                continue
            }
            if let start = code.range(of: "Trace.") {
                traceDepth = parenBalance(code[start.lowerBound...])
                continue
            }
            guard containsJapanese(code) else { continue }
            checked += 1
            if !code.contains("bundle: .module") {
                offenders.append(Offender(line: index + 1, text: line.trimmingCharacters(in: .whitespaces)))
            }
        }
        return (checked, offenders)
    }

    /// `//` から後ろを落とす。文字列の中の `//`（URL など）は残す。
    static func stripComment(_ line: String) -> String {
        var inString = false
        var previous: Character?
        var result = ""
        for character in line {
            if character == "\"", previous != "\\" { inString.toggle() }
            if !inString, character == "/", previous == "/" {
                result.removeLast()
                return result
            }
            result.append(character)
            previous = character
        }
        return result
    }

    static func parenBalance<S: StringProtocol>(_ code: S) -> Int {
        code.reduce(0) { $0 + ($1 == "(" ? 1 : $1 == ")" ? -1 : 0) }
    }

    /// ひらがな・カタカナ・漢字。記号（「」…—）だけの文字列は訳す対象にならないので数えない。
    static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value)
        }
    }

    // MARK: - 場所

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // NullnoteUITests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent()

    /// `Sources/NullnoteUI` の `.swift`。足あとの本体（`Trace.swift`）は除く。
    private static func sourceFiles() throws -> [URL] {
        let sources = packageRoot.appendingPathComponent("Sources/NullnoteUI")
        return try FileManager.default.contentsOfDirectory(atPath: sources.path)
            .filter { $0.hasSuffix(".swift") && $0 != "Trace.swift" }
            .sorted()
            .map { sources.appendingPathComponent($0) }
    }

    /// `.xcstrings` のうち、ここで見る部分だけ。
    private struct Catalog: Decodable {
        struct Entry: Decodable {
            let localizations: [String: Localization]?
        }
        /// 中身（`stringUnit` か `variations`）は問わない。あるかどうかだけ見る。
        struct Localization: Decodable {}

        let sourceLanguage: String
        let strings: [String: Entry]
    }
}
