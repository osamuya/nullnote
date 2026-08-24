# MarkdownCore

Markdown をエディタのシンタックスハイライト用トークン列に変換する、UI 非依存の Swift Package。

`Foundation` にのみ依存する。**AppKit / UIKit / SwiftUI を import してはならない。** この制約が、
macOS 版と iOS 版でロジックを共有するための唯一の担保になっている。

- 対応プラットフォーム: macOS 14+ / iOS 17+
- 対応記法: CommonMark 基本セット + GFM 拡張（後述の「既知の制限」を参照）

| 分類 | 記法 |
|---|---|
| ブロック | ATX 見出し、水平線、箇条書き・番号付きリスト、引用（ネスト可）、フェンス付き／インデントされたコードブロック、HTML コメント |
| インライン | 強調 `*` `_`、強い強調 `**` `__` `***`、インラインコード、リンク、画像、山括弧オートリンク、バックスラッシュエスケープ |
| GFM 拡張 | 表、タスクリスト `- [ ]` `- [x]`、取り消し線 `~` `~~`、拡張オートリンク（裸の URL・メールアドレス） |

## 使い方

```swift
import MarkdownCore

let tokenizer = MarkdownTokenizer()

for token in tokenizer.tokenize(source) {
    let range = token.nsRange(in: source)
    switch token.kind {
    case .heading(let level):
        textStorage.addAttribute(.font, value: headingFont(level), range: range)
    case .marker:
        textStorage.addAttribute(.foregroundColor, value: dimmedColor, range: range)
    default:
        break
    }
}
```

## 設計

### トークン列であって、ドキュメント木ではない

`MarkdownToken` は「ソース上の範囲」と「そこに与える意味」の組でしかない。
プレビューや HTML 出力に必要なネスト構造は持たない。エディタが必要とするのは
`NSTextStorage` に属性を貼るための範囲だけであり、そこに絞ることで
キー入力ごとの再計算を軽く保っている。

### トークンは重なる

`# **見出し**` は見出しトークンと強調トークンの両方を生む。
配列は **外側のトークンが内側より先** に並ぶため、配列順どおりに属性を適用すれば
内側の指定が外側に上書きされて正しく重なる。位置順ではないので、
位置でソートし直すとこの保証は失われる。

### 1行の解析は「直前の状態」と「次の行」にしか依存しない

```
tokenizeLine(text, range:, stateBefore:, nextLine:) -> MarkdownLineTokens
                                                        ├─ tokens
                                                        └─ stateAfter  ← 次の行の stateBefore
```

`MarkdownBlockState` は 6 通りしかない（`blank` / `paragraph` / `indentedCode` /
`fencedCode` / `tableDelimiterExpected` / `tableBody`）。編集された行から再解析を始め、
`stateAfter` が以前の値と一致した行で打ち切れば、差分更新はモデルを変えずに後から載せられる。
差分更新そのものは未実装。

`nextLine` は表のためだけにある。表のヘッダ行は「次の行が列数の一致する区切り行である」
ことでしか判別できないため、1行だけ先読みする。渡さなければ表は始まらない。
後ろ向きの参照は無いので、差分更新の打ち切り判定はこれまでどおり成立する。

### レイヤの境界

```
MarkdownCore  ─ Foundation のみ。プラットフォーム非依存
      ↑
   UI 共通層   ─ SwiftUI。トークン → 属性のマッピング
      ↑
 macOS / iOS  ─ NSViewRepresentable / UIViewRepresentable
```

トークンから色やフォントへのマッピングは MarkdownCore の責務ではない。
テーマや配色は上の層に置くこと。

## 既知の制限

エディタのハイライトに必要な範囲で割り切っている。CommonMark 準拠のレンダラではない。

| 項目 | 挙動 |
|---|---|
| Setext 見出し（`===` / `---` の下線） | 未対応。`---` は水平線として扱う |
| 参照リンク `[text][id]` とリンク定義 | 未対応。ただのテキストになる |
| HTML ブロック / インライン HTML | **コメント `<!-- … -->` のみ対応**（`.htmlComment`）。それ以外の HTML は未対応 |
| ハードブレーク（行末の2スペース） | 未対応 |
| 脚注 `[^1]` | 未対応（GFM 仕様には含まれない GitHub 独自拡張） |
| リストのネスト・段落の所属 | 追跡しない。マーカーの位置だけを見る |
| 引用の中で開いたフェンス | 状態が引用の外へ漏れる。`> ` もコードとして着色される |
| 引用の中の表 | 未対応。先読みが引用の内側まで届かない |
| 強調の対応付け | CommonMark の delimiter-run アルゴリズムの近似。`***x***` や `**a *b***` は正しく解けるが、`*a**` のような退化した入力は仕様と異なる |
| 表の本体行 | パイプを含まない行で表を終わらせる。GFM は1セルの行として続けるので、そこだけ挙動が異なる |
| 表の桁揃え | 区切り行の `:` は認識するが、配置情報はトークンに載せない（描画側の責務） |
| 拡張オートリンクの末尾判定 | 句読点と対応の取れない `)` を落とす簡略版。GFM の完全な仕様ではない |

強調とリンクのネストは深さ 8 で打ち切る（`InlineScanner.maximumNestingDepth`）。
引用のネストも同様に深さ 8 まで（`MarkdownTokenizer.maximumQuoteDepth`）。

## 速さ

`tokenize` の実測（release ビルド、Apple Silicon）。

| 文字数 | 所要 |
|---|---|
| 500 | 0.06 ms |
| 1万 | 1.0 ms |
| 5万 | 5.3 ms |

打鍵ごとに全文をかけ直しても、5万文字で 1フレーム（16.7 ms）に収まる。
差分更新が要るのはこれを超えてから。設計上は載せられるようにしてあるが、
必要になっていないので実装していない。

## 検証

```sh
swift test                                                  # macOS
xcodebuild -scheme MarkdownCore -destination 'generic/platform=iOS' build   # iOS ビルド確認
```

iOS ビルドは CI に入れておくこと。UIKit 非依存が崩れたときに、ここで気づけなくなる。
