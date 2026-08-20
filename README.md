# Nullnote

Markdown エディタ。macOS 版が動いている。同じロジックで iOS 版へ展開する。

## 3つのスクリプト

`Apps/Nullnote-macOS/` に3つある。**「誰のためのビルドか」で分かれている。**

| | `run.sh` | `install.sh` | `release-dmg.sh` |
|---|---|---|---|
| 目的 | **直した所を今すぐ確かめる** | **自分の Mac で常用する** | **他人に配る** |
| 構成 | Debug | Release | Release |
| 署名 | Apple Development | Apple Development | **Developer ID ＋ 公証** |
| 出来上がり | DerivedData の中 | `/Applications/Nullnote.app` | `build/Nullnote-<版>.dmg` |
| かかる時間 | 短い | 中くらい | **長い**（公証待ちで数分） |
| 他人の Mac で動くか | ❌ | ❌ | ✅ |

```sh
cd Apps/Nullnote-macOS

./run.sh                  # 新規書類で起動
./run.sh ~/Desktop/a.md   # ファイルを開いて起動
./install.sh              # /Applications に反映
./release-dmg.sh          # 配布用 DMG を作る
```

**`install.sh` と `release-dmg.sh` は独立している。**
DMG を作っても `/Applications` は更新されないし、逆も同じ。
両方に反映したいならそれぞれ実行する。

### ふだんの流れ

```
コードを直す
    ↓
swift test                 速い。ここで落ちたら先に進まない
    ↓
./run.sh                   触って確認
    ↓
（良ければ）./install.sh    自分の常用アプリに反映
    ↓
（配る段になったら）
バージョンを上げる → ./release-dmg.sh → DMG をサイトに置く
```

ビルドだけしたいときは、スクリプトを介さず直接叩けばよい。

```sh
cd Apps/Nullnote-macOS && xcodebuild -scheme Nullnote build
```

### バージョンを上げる

`Apps/Nullnote-macOS/Nullnote.xcodeproj/project.pbxproj` の
`MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を書き換える（**Debug / Release の2か所ずつ**）。
DMG のファイル名は `MARKETING_VERSION` から自動で付く。

## 現在地

| レイヤ | 状態 |
|---|---|
| `Packages/MarkdownCore` | ✅ 完成（72 テスト） |
| `Packages/NullnoteUI` | ✅ 完成（315 テスト） |
| `Apps/Nullnote-macOS` | ✅ 動作（起動・ファイル読み込み確認済み） |
| `Apps/Nullnote-iOS` | ⬜ 未着手（パッケージは iOS ビルド通過済み） |

見た目は `Apps/Nullnote-macOS/Screenshots/` を参照。

## ドキュメント

| | |
|---|---|
| [docs/01-native-app-anatomy.md](docs/01-native-app-anatomy.md) | macOS アプリの構造。ソースが `.app` になるまで、リンク、DerivedData、署名 |
| [docs/02-decision-log.md](docs/02-decision-log.md) | なぜこの作りにしたか。捨てた案、実測値、見つけた不具合 |
| [docs/04-development-flow.md](docs/04-development-flow.md) | 開発の手順。ビルド・起動・テスト・インストール |
| [docs/03-release-plan.md](docs/03-release-plan.md) | 配布の段取りと作業ログ。署名・公証でつまずいた点 |
| [Packages/MarkdownCore/README.md](Packages/MarkdownCore/README.md) | パースの設計と既知の制限 |
| [Packages/NullnoteUI/README.md](Packages/NullnoteUI/README.md) | ハイライトとプレビューの実装 |
| [Apps/Nullnote-macOS/README.md](Apps/Nullnote-macOS/README.md) | ターゲット設定、UTType、操作方法 |


## Specification

### 2026-08-06
- エディタのデフォルトは、画面がひとつで左右に分かれていない。上部のボタンで左右でプレビューする。
- 対応記法は CommonMark 基本セット + GFM 拡張（表、タスクリスト、取り消し線、拡張オートリンク）
- Light と Dark のテーマ
  → 実装済み。設定でシステム追従／ライト／ダークを切り替える
- 設定は可能な限りシンプルにする。文字サイズなどのみ
  → 実装済み。テーマと文字サイズの2つだけ
- 左端に見出しの目次（階層表示・開閉・クリックで移動）
  → 実装済み（[docs/02-decision-log.md](docs/02-decision-log.md) の D-15）
- 画面のスクロール時に、左右の領域が可能な限り同期してスクロールする。（大幅にずれてしまう場合は、同期をキャンセルしてよい）
  → 実装済み。行番号で対応付けてブロック単位で吸着させるため、そもそも大きくずれない。
  いまはエディタ → プレビューの一方向（[docs/02-decision-log.md](docs/02-decision-log.md) の D-10）

### 2026-08-08
- 検索機能：ヒットした部分のハイライト
  → 実装済み。⌘F で検索の帯を出し、ヒットを塗って件数を出す。∧ ∨ と ⌘G / ⇧⌘G で前後へ送る
  （[docs/02-decision-log.md](docs/02-decision-log.md) の D-21）
-  [Command + D]のヒットした単語の同時選択
  → 実装済み。⌘D で同じ語を1つずつ足し、⌃⌘G で全部選ぶ。打ち込み・削除が全箇所に効く。
  矢印キーでカーソルをそろえて動かせる（⇧←→ で選び直し）。置換はこちらの役目
  （[docs/02-decision-log.md](docs/02-decision-log.md) の D-28）

| 項目 | 設定値 |
| --- | --- |
| **Product Name** | Nullnote |
| **Bundle Identifier** | com.roughlang.Nullnote |
| **Interface** | SwiftUI |
| **Language** | Swift 6.0 |
| **最低 OS** | macOS 14 / iOS 17 |

## 構成

```text
MarkdownEditor/
├─ Packages/
│  ├─ MarkdownCore/          ← Foundation のみ。パース・トークン化
│  │  ├─ README.md           ← 設計と既知の制限
│  │  ├─ Sources/MarkdownCore/
│  │  │  ├─ MarkdownToken.swift
│  │  │  ├─ MarkdownBlockState.swift
│  │  │  ├─ MarkdownLineTokens.swift
│  │  │  ├─ MarkdownTokenizer.swift
│  │  │  └─ Internal/{Line,Block,Inline,Table}Scanner.swift
│  │  └─ Tests/MarkdownCoreTests/
│  └─ NullnoteUI/            ← SwiftUI 共通層
│     ├─ README.md
│     ├─ Sources/NullnoteUI/
│     │  ├─ Platform.swift            # AppKit/UIKit の差を吸収する唯一の場所
│     │  ├─ MarkdownTheme.swift       # 配色・文字サイズ
│     │  ├─ MarkdownHighlighter.swift # トークン → 文字属性
│     │  ├─ MarkdownEditorView.swift  # NSTextView / UITextView
│     │  ├─ PreviewModel.swift        # AST → 中間表現
│     │  ├─ MarkdownPreview.swift     # 中間表現 → SwiftUI
│     │  ├─ FileWatcher.swift         # 外の変更を知る
│     │  ├─ ThreeWayMerge.swift       # 3つの版の突き合わせ
│     │  ├─ ImageSource.swift         # 画像の場所の解釈
│     │  ├─ DocumentSearch.swift      # 文書内検索のヒットと現在位置
│     │  ├─ MultiSelection.swift      # ⌘D の語の切り出しと一括書き換え
│     │  └─ SearchField.swift         # ヘッダーの検索欄
│     └─ Tests/NullnoteUITests/
├─ Apps/
│  ├─ Nullnote-macOS/        ← macOS アプリターゲット
│  └─ Nullnote-iOS/          ← iOS アプリターゲット（未着手）
```

## 依存の向き

```
Apps/Nullnote-macOS ──┐
                      ├─→ Packages/NullnoteUI ──→ Packages/MarkdownCore
Apps/Nullnote-iOS   ──┘         │
                                └─→ apple/swift-markdown（プレビューのみ）
```

守るべき制約はふたつ。

> **1. MarkdownCore は AppKit / UIKit / SwiftUI を import しない。**
>
> **2. アプリターゲットにロジックを書かない。**

iOS 展開でやり直しになる最大の原因が、この2つの破れ。
`xcodebuild -destination 'generic/platform=iOS' build` を CI に入れて機械的に守る。

プラットフォーム差分は `NullnoteUI` の `Platform.swift` と `MarkdownEditorView.swift`
の2ファイルにしかない。ここが増え始めたら黄信号。

## 編集とプレビューでパーサが違う

| 用途 | パーサ | 実測（release） |
|---|---|---|
| エディタのハイライト | `MarkdownCore`（トークン列） | 1万文字で 1.0 ms、5万文字で 5.3 ms |
| プレビューの描画 | `swift-markdown`（AST） | 1万文字で 9.2 ms、5万文字で 45.7 ms |

トークン列はネスト構造を持たないので描画には使えない。
AST は打鍵ごとに回すには重い（5万文字で 1フレームの3倍）。
統合しようとすると、遅くなるだけで見返りが無い。

エディタは打鍵ごとに全文をトークン化するが、属性を貼るのは変わった行だけ
（1.8万文字で打鍵1回 3.6 ms。全文を貼り直していた頃は 30 ms かかっていた → D-24）。
プレビューは入力が止まって 150 ms 後に解析する。

## 検証

```sh
swift test --package-path Packages/MarkdownCore      # 72 tests
swift test --package-path Packages/NullnoteUI        # 242 tests

# iOS ビルド（UI 依存が混入していないことの確認）
cd Packages/MarkdownCore && xcodebuild -scheme MarkdownCore -destination 'generic/platform=iOS' build
cd Packages/NullnoteUI   && xcodebuild -scheme NullnoteUI   -destination 'generic/platform=iOS' build

# アプリ
cd Apps/Nullnote-macOS && xcodebuild -scheme Nullnote build
```

## 次の一歩

**リリースまでの段取りは [docs/03-release-plan.md](docs/03-release-plan.md) にまとめてある。**
第1段階＝ローカル常用、第2段階＝App Store 公開。

機能面の候補:

1. コードブロックのシンタックスハイライト（言語名は既に取れている）
2. Markdown 記法の入力補助（⌘B で `**` を挿入する等）
3. 差分ハイライト（長文で引っかかるようになったら。`MarkdownLineTokens.stateAfter` の収束で打ち切る）
4. iOS アプリターゲット（`Apps/Nullnote-iOS/README.md` に手順）

## リリース前に確認すること

- 署名をアドホックから Developer ID / App Store の証明書に差し替える
- App Store での名称検索
- 商標（日本: 特許庁 J-PlatPat / 米国: USPTO）
- ドメインの空き

```
~/Library/Developer/Xcode/DerivedData/Nullnote-…/Build/Products/Debug/Nullnote.app
```