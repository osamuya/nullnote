# NullnoteUI

macOS 版と iOS 版が共有する SwiftUI レイヤ。トークンや AST を、実際の見た目に変える。

- 対応プラットフォーム: macOS 14+ / iOS 17+
- 依存: `MarkdownCore`（自作）、`apple/swift-markdown`（プレビューのみ）

## 中身

| ファイル | 役割 |
|---|---|
| `Platform.swift` | AppKit と UIKit の差を吸収する**唯一の場所** |
| `MarkdownTheme.swift` | 配色・文字サイズ・外観の指定 |
| `MarkdownHighlighter.swift` | `MarkdownCore` のトークン → 文字属性 |
| `MarkdownEditorView.swift` | `NSTextView` / `UITextView` の Representable。焦点の出入りを知らせる `FocusReportingTextView` もここ |
| `CodeSyntax.swift` | コードブロックの色分け（キーワード／文字列／コメント／数値） |
| `LineNumberGutter.swift` | 編集画面の行番号。テキストビューの左余白に描く。macOS のみ |
| `PreviewModel.swift` | swift-markdown の AST → プレビュー用の中間表現 |
| `MarkdownPreview.swift` | 中間表現 → SwiftUI ビュー |
| `PreviewText.swift` | プレビュー1ブロック分の描画。リンクのホバーもここ |
| `DocumentOutline.swift` | 見出しを拾って目次の木を作る |
| `OutlineView.swift` | 目次の表示と開閉 |
| `DocumentSearch.swift` | 文書内検索。ヒットの求め方と、いま何番目かの持ち方 |
| `SearchField.swift` | ヘッダーに置く検索欄。入力欄・件数・前後への送り |
| `SplitPane.swift` | 編集とプレビューを左右に並べる。比率を保つ |
| `StatusBar.swift` | 窓の下端の帯。テーマ・文字サイズ・行数・大きさ |
| `SystemAppearance.swift` | `.system` を具体的な配色に解決し、OS の変化を見張る |
| `LineIndex.swift` | 文字位置 ⇄ 行番号。スクロール同期と行番号で引く |

## 配色

`MarkdownTheme.standard()` の値と、背景に対するコントラスト比（実測）。

| 役割 | ライト | 比 | ダーク | 比 |
|---|---|---|---|---|
| ページ背景 | `#F5F5F5` | — | `#293238` | — |
| 本文 | `#1C1C1E` | 15.61 | `#E2E2E6` | 10.11 |
| 見出し | `#0A0A0C` | 18.14 | `#F5F5F8` | 12.00 |
| 引用 | `#696E7A` | 4.68 | `#969BA8` | 4.70 |
| リンク | `#1469C8` | 4.96 | `#69AAFA` | 5.43 |
| チェックボックス | `#0080FF` | 3.48 | `#0080FF` | 3.44 |
| コード文字 | `#B43C5A` | 4.69※ | `#F096AF` | 5.20※ |
| コードブロック背景 | `#EAEAEE` | 1.10 | `#323C43` | 1.16 |
| 記法（`#` `*` `\|`） | `#A8AAB2` | 2.13 | `#767882` | 2.97 |
| 表の見出し行の背景 | `#EAEAEE` | 1.10 | `#323C43` | 1.16 |
| 表の罫線 | `#A8AAB2` 45% | — | `#767882` 45% | — |
| 目次の選択行 | `#A8AAB2` 32% | — | `#767882` 32% | — |
| 取り消した文字 | `#696E7A` | 4.68 | `#969BA8` | 4.70 |
| 検索のヒット | `#FFD60A` | 12.05† | `#FFD60A` | 12.05† |
| 検索の現在のヒット | `#FF9500` | 7.74† | `#FF9500` | 7.74† |
| ヒットの上の文字 | `#1C1C1E` | — | `#1C1C1E` | — |

※ コード文字はコードブロック背景に対する比。
† 検索のヒットは**背景色**。比は、その上に載る `searchMatchText`（`#1C1C1E`）に対して測っている。
ページ背景との比は、ライトが 1.29 / 2.02、ダークが 9.26 / 5.94。

**検索の3色だけ外観に追従しない。** ヒットの上の文字を暗い色で固定した見返りに、
背景へ明るい原色をそのまま置ける。追従させるとダークでは白い文字を載せることになり、
背景を暗く濁らせるほかなくなる（黄色が茶色になり、ダークで特に見分けにくかった）。

**目安**: 本文は 4.5 以上、図形・大きな文字は 3.0 以上。
コードブロック背景はページ背景との「差」で、1.1〜1.3 でパネルとして認識できる。

記法の色だけ意図的に低い。**読ませる文字ではなく、消しておきたい文字**なので、
本文より沈ませてある。ここを 4.5 まで上げると記法が本文と同じ強さで主張してしまう。

色を変えるときは、単体で決めず**背景との比まで測ること**。
ページ背景を変えたときにコードブロック背景が同化して消えかけた（差 1.01:1）実例がある。

## テーマ（ライト／ダーク）

**配色は1組しか持たない。** 色はすべて外観に追従する動的な色
（`NSColor(name:dynamicProvider:)` / `UIColor { traits in }`）として定義してあり、
`MarkdownTheme.appearance` が「どちらで解決するか」を決める。

```swift
MarkdownTheme.standard(fontSize: 14, appearance: .dark)
```

| 指定 | AppKit | UIKit | SwiftUI（macOS） |
|---|---|---|---|
| `.system` | `NSApp.effectiveAppearance` | `.unspecified` | `SystemAppearance.current`（`.light` か `.dark`） |
| `.light` | `NSAppearance(named: .aqua)` | `.light` | `.light` |
| `.dark` | `NSAppearance(named: .darkAqua)` | `.dark` | `.dark` |

**`.system` でも nil を渡さない。** AppKit も SwiftUI も、
明示指定から nil（＝継承・好みなし）へ戻したとき、配色が前のまま残る。
「ライト → システム」で編集画面が（B-8）、プレビューとフッターが（B-12）ライトのままになった。

そのため:

- AppKit へは `platformAppearance`（非オプショナル）
- SwiftUI へは `View.markdownColorScheme(_:)`。**`preferredColorScheme` を直に呼ばないこと**

配色を固定した以上、OS の切り替えには自分で追従する必要がある。
`SystemAppearance` が `NSApp.effectiveAppearance` を KVO で見張っている。

配色を2組持って切り替える方法もあるが、片方だけ直して食い違う事故が起きやすい。
動的な色に寄せておけば、色の定義は1か所で済み、システム追従もタダで付いてくる。

**属性文字列を貼り直す必要も無い。** 動的な色は描画時に解決されるので、
外観を変えたらそのまま新しい色で描かれる。
（例外はプレビューのインラインコードで、こちらは解析時に色を焼き込むため組み直す）

## スクロール同期

エディタとプレビューは**行番号で対応付ける**。

```
エディタ                                      プレビュー
表示範囲の左上の文字位置                       PreviewBlock.sourceLine
  → characterIndexForInsertion(at:)             ↑ swift-markdown の SourceRange から
  → LineIndex で行番号へ                        blockID(containing:) で対応するブロックを探し
  → topVisibleLine (Binding<Int>)  ──────────→  ScrollViewReader で上端に合わせる
```

```swift
MarkdownEditorView(text: $text, theme: theme, topVisibleLine: $line)
MarkdownPreview(source: text, theme: theme, anchorLine: line)
```

### なぜ比率で合わせないか

エディタとプレビューでは行の高さが違う。見出しは拡大され、コードブロックには余白が付き、
表は罫線を持つ。スクロール量を比率で配分すると、下へ行くほどずれが積み上がる。

### 割り切っていること

- **ブロック単位でしか合わない。** 長い段落の途中までスクロールしても、
  プレビューはその段落の先頭で止まる。段落・見出し・リストはそれぞれ別ブロックなので、
  実際の文書ではおおむね数行おきに追従する
- **エディタ → プレビューの一方向。** プレビュー側を手で動かしても、エディタは動かない。
  逆方向も入れるとスクロールの取り合いになるため、必要になってから考える
- スクロール中は毎回 `Binding<Int>` に書き戻すことになるので、
  行番号が変わったときだけ書く。`NSTextView.string` の読み直しも避けている
  （呼ぶたびに文字列を作り直すため）

## 文書内検索

判定は**大文字小文字を無視した部分一致だけ**。正規表現も単語単位も持たない。

```
検索語 ──→ DocumentSearch.matches(of:in:)   [NSRange]（UTF-16、重なり無し）
              ↓
           SearchSession       ヒットの一覧と、いま何番目か
              ├─ highlight ────────→ MarkdownEditorView（塗るだけ）
              └─ currentRange ─────→ EditorSelectionRequest（画面の中ほどへ＋カーソル）
```

検索欄はヘッダー（ツールバー）の 🔍 の左に出る。置き場所を決めるのはアプリ側で、
`MarkdownSearchField` 自体はただの横並びなので、iOS では別の場所に置ける。

**塗ることと移動することを分けてある。** 本文が変わるたびにヒットは数え直すが、
それで画面を動かすと、検索欄を出したまま編集しているだけでカーソルが飛ぶ。
移動するのは前後へ送ったときと検索語を変えたときだけで、
そのときは `EditorSelectionRequest`（`EditorScrollRequest` と同じく `id` を持つ依頼）を出す。

塗り直しは**全文を貼り直す**。検索の色だけを剥がす手が無いため
（コードブロックの背景と `.backgroundColor` の区別が付かない）。
ハイライトは5万文字で 5.3 ms なので、送るたびに走らせても間に合う。

ヒットの上は**文字色も `searchMatchText` に差し替える**。背景だけ変えると、
コードブロックの構文色（紫・緑）の上に黄色が来て読めない組み合わせが出る。
見出しの色もここで落ちるが、読めることを優先している。

**ヒットの範囲は「選択」しない。カーソルを置くだけ。** 検索欄に入力の焦点が
あるあいだ、テキストビューは非アクティブなので、AppKit が選択範囲を
`unemphasizedSelectedTextBackgroundColor`（灰色）で塗る。これは属性の背景色より
**後に**描かれるため、いま見ているヒットが灰色に覆われる（B-13）。
長さ 0 のカーソルなら塗りが出ず、検索欄を閉じたあとそのまま編集も続けられる。

`SearchSession.refresh(in:)` は、いま見ていた位置以降の最初のヒットを選び直す。
検索語を1文字足すたびに文書の先頭へ戻されないようにするため。

## 編集とプレビューでパーサを分けている

| 用途 | パーサ | 実測（release） |
|---|---|---|
| エディタのハイライト | `MarkdownCore`（トークン列） | 1万文字で 1.0 ms、5万文字で 5.3 ms |
| プレビューの描画 | `swift-markdown`（AST） | 1万文字で 9.2 ms、5万文字で 45.7 ms |

プレビュー用の AST は打鍵ごとに回すには重い（5万文字で 1フレーム 16.7 ms の3倍）。
逆にトークン列はネスト構造を持たないので描画には使えない。役割を分けるのが正しい。

そのうえで:

- **エディタ**は打鍵ごとに全文をトークン化して属性を貼り直す。
  5万文字で 5.3 ms なので、いまは全文で足りている。長文で引っかかるようになったら
  `MarkdownLineTokens.stateAfter` の収束を使った差分更新に切り替える。
- **プレビュー**は入力が止まってから 150 ms 後に解析する（`task(id:)` のデバウンス）。

## 見た目に出すには具体的な属性が要る

プレビューのインライン装飾は `inlinePresentationIntent` に載せているが、
SwiftUI の `Text` が実際に描いてくれるのは **強調と強い強調だけ**。
取り消し線と等幅は、意味づけとは別に具体的な属性も指定している。

| 装飾 | 併せて指定している属性 |
|---|---|
| 取り消し線 | `strikethroughStyle`（`.thick`）、`strikethroughColor`、`foregroundColor` |
| インラインコード | `font`（等幅）、`foregroundColor` |

取り消し線は `.single` だと細く、ぱっと見でふつうの文字と区別が付かない。
`.thick` にしたうえで、文字自体も本文より沈ませている（`theme.struckText`）。

インラインコードのフォントには解析時点のテーマの文字サイズが焼き込まれる。
そのため `MarkdownPreview` は文字サイズが変わったときも解析し直す。

## 裸の URL の扱い

swift-markdown は GFM の `table` / `strikethrough` / `tasklist` は有効にしているが、
**`autolink` 拡張は有効にしていない**。`MarkdownCore` は裸の URL をリンクとして
着色するため、そのままだとエディタとプレビューで見え方がずれる。

`PreviewModel` 側で `NSDataDetector` を使って補い、`MarkdownCore` と同じ条件
（`http://` `https://` `www.` またはアットマークを含む）まで絞り込んでいる。

## プラットフォーム差分の置き場所

```
#if canImport(AppKit)  … NSTextView / NSColor / NSFont
#else                  … UITextView / UIColor / UIFont
```

この分岐があるのは `Platform.swift` と `MarkdownEditorView.swift`、
それに `MarkdownTheme.activeLineNumber`（システム色の名前が違う）だけ。
`LineNumberGutter.swift` はファイルごと macOS 限定にしてある
（`UITextView` に `drawBackground(in:)` の差し込み口が無く、iOS では別の作りになるため）。

ここが増え始めたら、iOS 版が macOS 版の作り直しになる兆候。

## 数え方をそろえる

行数は2か所で数えている。**必ず同じ答えになること。**

| どこ | 何を使うか |
|---|---|
| 行番号 | `LineIndex`（＋末尾が改行のときの空行を `extraLineFragmentRect` で補う） |
| フッター | `DocumentSize.lineCount` |

末尾が改行のとき、`enumerateLineFragments` はその後ろの空行を渡してこない。
補わないと行番号だけ1つ少なくなる。両者の一致は `StatusBarTests` で縛ってある。

大きさは **UTF-8 のバイト数**。文字数ではない（日本語は1文字3バイト）。

## 既知の制限

- 差分ハイライトは未実装（上記のとおり、いまは全文を貼り直す）
- 画像はプレビューでも描かない。代替テキストを表示するだけ
- チェック済みのタスク項目の本文に取り消し線は引かない
- エディタのコードブロックの背景は行ごとに文字幅ぶんしか塗られない
- 検索はエディタだけ。プレビュー側には塗らない（スクロール同期で追従はする）
- 検索を開いたときの起点は文書の先頭。カーソルのある場所からは始まらない
- 置換は無い（D-21。同じ語をまとめて直すのは、後から入れる複数選択の役目）

## 検証

```sh
swift test                                                                   # macOS
xcodebuild -scheme NullnoteUI -destination 'generic/platform=iOS' build      # iOS ビルド確認
```

iOS ビルドは CI に入れておくこと。UIKit 非依存が崩れたときに、ここで気づけなくなる。
