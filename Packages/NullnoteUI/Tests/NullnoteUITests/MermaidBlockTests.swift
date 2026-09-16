import Foundation
import Testing
@testable import NullnoteUI

@Suite("mermaid の図")
struct MermaidBlockTests {

    func blocks(_ source: String) -> [PreviewBlock] {
        PreviewBuilder.build(source, theme: .standard())
    }

    func firstMermaid(_ source: String) -> String? {
        for block in blocks(source) {
            if case .mermaid(let code) = block.content { return code }
        }
        return nil
    }

    // MARK: - 見分け

    @Test("```mermaid は図として取り出される")
    func recognised() {
        let code = firstMermaid("```mermaid\nflowchart TB\n  A --> B\n```")
        #expect(code == "flowchart TB\n  A --> B")
    }

    @Test("大文字で書かれていても図として扱う")
    func caseInsensitive() {
        #expect(firstMermaid("```Mermaid\nflowchart TB\n  A --> B\n```") != nil)
        #expect(firstMermaid("```MERMAID\nflowchart TB\n  A --> B\n```") != nil)
    }

    @Test("言語の後ろに何か書かれていても、最初の語だけを見る")
    func extraInfoString() {
        // cmark は ``` の後ろを丸ごと language に入れてくる。
        #expect(firstMermaid("```mermaid theme=dark\nflowchart TB\n  A --> B\n```") != nil)
    }

    @Test("ほかの言語は今までどおりコードブロックのまま")
    func otherLanguages() {
        #expect(firstMermaid("```swift\nlet x = 1\n```") == nil)
        // **前方一致で拾わない。** mermaidjs という言語名が来ても図にはしない。
        #expect(firstMermaid("```mermaidjs\nflowchart TB\n  A --> B\n```") == nil)
        #expect(firstMermaid("```\nflowchart TB\n```") == nil)
    }

    @Test("中身が空のあいだは図にしない")
    func emptyStaysCode() {
        // ```mermaid を打った直後。空の枠が出たり消えたりしないように、
        // 中身が入るまではコードのまま置く。
        #expect(firstMermaid("```mermaid\n```") == nil)
        #expect(firstMermaid("```mermaid\n\n  \n```") == nil)

        guard case .codeBlock(_, let language)? = blocks("```mermaid\n```").first?.content else {
            Issue.record("コードブロックとして残っていない")
            return
        }
        #expect(language == "mermaid")
    }

    @Test("図の記述は中身を変えずに素通しする")
    func passedThroughVerbatim() {
        // 解釈は mermaid.js に任せる。こちらで整形しない。
        let source = """
        ```mermaid
        flowchart TB
            subgraph S["名前"]
                A["1行目\\n2行目"]
            end
            style A fill:#fee,stroke:#c00
        ```
        """
        let code = firstMermaid(source)
        #expect(code?.contains("subgraph S[\"名前\"]") == true)
        #expect(code?.contains("\\n") == true)
        #expect(code?.contains("style A fill:#fee,stroke:#c00") == true)
    }

    @Test("図は元の行番号を持つ")
    func keepsSourceLine() {
        // エディタとのスクロール同期は行番号を手がかりにする。
        let source = "# 見出し\n\n本文\n\n```mermaid\nflowchart TB\n  A --> B\n```"
        guard let block = blocks(source).first(where: {
            if case .mermaid = $0.content { return true } else { return false }
        }) else {
            Issue.record("図が取れていない")
            return
        }
        #expect(block.sourceLine == 5)
    }

    // MARK: - 器

    @Test("図を描く器が束に入っている")
    func resourcesArePresent() async {
        // `.copy("Mermaid")` を落とすと、図が一切描けなくなる。
        // ビルドは通ってしまうので、ここで見張る。
        let host = await MermaidCoordinator.hostURL
        guard let host else {
            Issue.record("Mermaid/host.html が Bundle.module に無い")
            return
        }
        #expect(FileManager.default.fileExists(atPath: host.path))

        // host.html は同じ folder の mermaid.min.js を相対で読む。
        let script = host.deletingLastPathComponent().appendingPathComponent("mermaid.min.js")
        #expect(FileManager.default.fileExists(atPath: script.path))
    }

    @Test("器は外へ出ていく記述を持たない")
    func hostDoesNotReachOut() async throws {
        guard let host = await MermaidCoordinator.hostURL else {
            Issue.record("Mermaid/host.html が Bundle.module に無い")
            return
        }
        let html = try String(contentsOf: host, encoding: .utf8)

        // 図はネットワークを見にいかない。外部の URL を書き足すと、
        // 文書を開いただけで接続することになる。
        #expect(!html.contains("https://"))
        #expect(!html.contains("http://"))
        // 本文は他所から来た文書のことがある。取り込みの緩和を外さない。
        #expect(html.contains("securityLevel: 'strict'"))
        #expect(html.contains("default-src 'none'"))
    }

    // MARK: - 積み方の切り替え

    @Test("図があるかどうかを、引用やリストの中まで見て判断する")
    func containsDiagram() {
        // **この判断がプレビューの積み方を決める。** 取りこぼすと `LazyVStack` のままになり、
        // 図の下の本文が出せなくなる（実測：図5個で 977pt 足りない。D-65）。
        #expect(blocks("```mermaid\nflowchart TB\n  A --> B\n```").containsDiagram)

        // 引用の中。
        #expect(blocks("> ```mermaid\n> flowchart TB\n>   A --> B\n> ```").containsDiagram)

        // リストの中。
        #expect(blocks("- 項目\n\n  ```mermaid\n  flowchart TB\n    A --> B\n  ```").containsDiagram)

        // 合流の印で割られた側。
        let conflict = """
        <<<<<<< Internal updates
        ```mermaid
        flowchart TB
          A --> B
        ```
        =======
        外の版
        >>>>>>> External updates
        """
        #expect(blocks(conflict).containsDiagram)
    }

    @Test("図が無ければ、今までどおり見えているところだけ組む")
    func withoutDiagram() {
        // ここが true になると、図と関係ない文書まで開くのが遅くなる
        // （42,290字の文書で 137ms → 651ms）。
        #expect(!blocks("# 見出し\n\n本文").containsDiagram)
        #expect(!blocks("```swift\nlet x = 1\n```").containsDiagram)
        #expect(!blocks("> 引用の中の本文\n\n- リスト").containsDiagram)
        // 空の ```mermaid は図にならないので、こちらも false のまま。
        #expect(!blocks("```mermaid\n```").containsDiagram)
    }

    // MARK: - 外へ出さない

    @Test("通すのは同梱したファイルだけ")
    func onlyFileURLsAllowed() {
        // **この判断が効かなくなっても、画面上は何も変わらない。**
        // `decidePolicyFor` の署名を崩すと WebKit から呼ばれなくなり、
        // 黙って素通しになる（実際に一度そうなっていた）。ここで縛る。
        #expect(MermaidCoordinator.allows(URL(string: "file:///tmp/host.html")) == true)

        #expect(MermaidCoordinator.allows(URL(string: "https://example.com")) == false)
        #expect(MermaidCoordinator.allows(URL(string: "http://example.com")) == false)
        #expect(MermaidCoordinator.allows(URL(string: "about:blank")) == false)
        #expect(MermaidCoordinator.allows(URL(string: "data:text/html,<b>x</b>")) == false)
        #expect(MermaidCoordinator.allows(nil) == false)
    }

    // MARK: - 拡大窓

    @Test("拡大窓のための仕掛けが器に入っている")
    func zoomHooksArePresent() async throws {
        guard let host = await MermaidCoordinator.hostURL else {
            Issue.record("Mermaid/host.html が Bundle.module に無い")
            return
        }
        let html = try String(contentsOf: host, encoding: .utf8)

        // Swift 側から呼ぶ名前。変えるなら両方そろえること。
        for name in ["setUpZoom", "zoomBy", "fitToWindow", "actualSize", "currentScale"] {
            #expect(html.contains("function \(name)") || html.contains("async function \(name)"),
                    "\(name) が器に無い")
        }
    }

    @Test("拡大の仕掛けは、プレビューに埋めたときに効かない")
    func zoomStylesAreScoped() async throws {
        guard let host = await MermaidCoordinator.hostURL else {
            Issue.record("Mermaid/host.html が Bundle.module に無い")
            return
        }
        let html = try String(contentsOf: host, encoding: .utf8)

        // 拡大窓用の指定は、すべて `body.zoom` の下に置く。
        // 素のままプレビューに効くと、図が幅に収まらなくなる。
        for line in html.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.contains("#box"), trimmed.contains("{") else { continue }
            guard trimmed.contains("max-width: none") || trimmed.contains("overflow: auto") else { continue }
            #expect(trimmed.hasPrefix("body.zoom"), "拡大窓用の指定が素で効いている: \(trimmed)")
        }
    }

    @Test("ドラッグで動かせるが、文字の上からは奪わない")
    func dragPansExceptOnLabels() async throws {
        guard let host = await MermaidCoordinator.hostURL else {
            Issue.record("Mermaid/host.html が Bundle.module に無い")
            return
        }
        let html = try String(contentsOf: host, encoding: .utf8)

        #expect(html.contains("function connectDragToPan"))
        // **この 1 行が、図の中の文字を選べるかどうかを決めている。**
        // 外すとドラッグが全面で移動になり、選択ができなくなる（D-65）。
        #expect(html.contains("if (e.target.closest && e.target.closest('foreignObject')) return;"))
        // 勢いよく動かしても止まらないよう、追いかけるのは window 側。
        #expect(html.contains("window.addEventListener('mousemove'"))
        #expect(html.contains("window.addEventListener('mouseup'"))
    }

    @Test("素のホイールは奪わない")
    func plainWheelIsNotTaken() async throws {
        guard let host = await MermaidCoordinator.hostURL else {
            Issue.record("Mermaid/host.html が Bundle.module に無い")
            return
        }
        let html = try String(contentsOf: host, encoding: .utf8)

        // 拡大は ⌘（または ctrl）を押しているときだけ。素のホイールを
        // preventDefault すると、移動（スクロール）ができなくなる。
        #expect(html.contains("if (!e.metaKey && !e.ctrlKey) return;"))
    }
}
