# Nullnote (macOS)

macOS アプリターゲット。

```sh
xcodebuild -scheme Nullnote -configuration Debug build
open Nullnote.xcodeproj      # Xcode で開く場合
```

## 構成

```text
Apps/Nullnote-macOS/
├─ Nullnote.xcodeproj/
├─ Nullnote/                  ← ファイル同期グループ。ここに .swift を置けば自動で入る
│  ├─ NullnoteApp.swift       # App 本体、DocumentGroup、メニュー
│  ├─ MarkdownDocument.swift  # FileDocument、UTType
│  ├─ DocumentView.swift      # エディタ／プレビューの切り替え、外の変更の取り込み、改名の検出
│  ├─ DocumentBridge.swift    # SwiftUI の下の NSDocument に触る唯一の窓口（改名もここ）
│  ├─ FolderAccess.swift      # フォルダを読む／書く許可。ブックマークで覚える
│  ├─ SettingsView.swift      # 設定（テーマ・行番号・ファイル名の同期・文字サイズ）
│  └─ AppSettings.swift       # UserDefaults のキー
├─ Supporting/
│  ├─ Info.plist              # UTType 宣言、日本語ロケール
│  └─ Nullnote.entitlements   # サンドボックス
└─ Screenshots/
```

`Nullnote/` は `PBXFileSystemSynchronizedRootGroup` なので、
**ファイルを追加したら Xcode 側の操作は要らない**。ディスクに置けば入る。

| 項目 | 値 |
| --- | --- |
| Bundle Identifier | com.roughlang.Nullnote |
| 最低 OS | macOS 14 |
| Swift | 6.0 言語モード |
| 署名 | ローカル実行用のアドホック（`CODE_SIGN_IDENTITY = "-"`） |

## ここに置くもの / 置かないもの

置くもの: `App`、`DocumentGroup`、`FileDocument`、メニュー、設定画面。

置かないもの: パースも描画も置かない。すべて `Packages/` 側にある。
このターゲットのコードが増え始めたら、iOS 版で書き直す羽目になる。

## UTType

Markdown には Apple 定義の UTType が無い。`Supporting/Info.plist` で
`net.daringfireball.markdown` を **Imported Type Identifier** として宣言し、
拡張子 `.md` / `.markdown` を紐付けている。ここを消すと `.md` を開けないアプリになる。

## メニューの言語

`CFBundleDevelopmentRegion = ja` と `CFBundleLocalizations` を Info.plist に入れてある。
これが無いと「ファイル」「編集」などの標準メニューが英語で出て、
自作のメニュー項目（日本語）と混ざる。

## 操作

| 操作 | ショートカット |
|---|---|
| 目次の表示／非表示 | ⌃⌘S（ツールバー左のボタンでも切り替わる） |
| プレビューの表示／非表示 | ⇧⌘P（ツールバー右のボタンでも切り替わる） |
| 検索 | ⌘F（ヘッダーの 🔍 ボタンでも開閉。esc で閉じる） |
| 次のヒットへ | ⌘G（検索欄で return、または ∨ ボタン） |
| 前のヒットへ | ⇧⌘G（∧ ボタン） |
| 文字を大きく／小さく | ⌘+ / ⌘− |
| 文字サイズを戻す | ⌘0 |
| 設定 | ⌘, |

## 設定

4つだけ。`UserDefaults`（サンドボックスのコンテナ内）に保存される。

| 項目 | キー | 値 |
|---|---|---|
| テーマ | `editorAppearance` | `system` / `light` / `dark` |
| 行番号を表示 | `editorShowsLineNumbers` | 既定 `true` |
| ファイル名と先頭の見出しを同期 | `syncsTitleWithFileName` | 既定 `false`（両方向） |
| 文字サイズ | `editorFontSize` | 10〜28 |

```sh
defaults read ~/Library/Containers/com.roughlang.Nullnote/Data/Library/Preferences/com.roughlang.Nullnote.plist
```

テーマは配色を2組持つのではなく、動的な色の解決先を上書きしている
（`docs/02-decision-log.md` の D-11）。

**ボタンの色は OS のアクセントカラーに従わない。** `.tint()` で `#FFD60A` に固定してある
（同 D-22）。利用者の設定で目次・検索・プレビューのボタンの色が変わらないようにするため。

macOS 標準の書類まわりは AppKit が用意する。**間違えやすいので明記しておく:**

| 操作 | ショートカット | 注意 |
|---|---|---|
| 保存 | ⌘S | |
| **複製** | **⇧⌘S** | Windows / Adobe 系の「別名で保存」と同じ打鍵だが、macOS では**複製**。複製直後の書類はディスク上に無いので、名前は付けられても場所とタグは選べない |
| 別名で保存… | **⌥⇧⌘S** | Option が要る。保存先を選びたいときはこちら |

保存パネルは既定で展開表示（ファイルブラウザ付き）にしてある。
折りたたみ状態だと保存先が「場所」ポップアップだけになるため
（`AppSettings.registerDefaults()`）。畳めばその選択が記憶される。

## 見た目

`Screenshots/` に現在の描画結果がある（ライト／ダーク × エディタ／プレビュー）。
画面収録の権限が無くても撮れるよう、`NSTextView` と `NSHostingView` を
オフスクリーンで描いて PNG に焼いたもの。

## 署名について

いまはローカル実行用のアドホック署名。配布するときは Developer ID か
App Store の証明書に差し替える（`CODE_SIGN_IDENTITY` と `DEVELOPMENT_TEAM`）。
サンドボックスとハードンドランタイムは最初から有効にしてある。

## サンドボックスと権限

| 権限 | 何のため |
|---|---|
| `app-sandbox` | App Store 配布の必須要件（D-9） |
| `files.user-selected.read-write` | 利用者が開いた書類の読み書き |
| `network.client` | 本文に書かれた `https://` の画像を読む（D-26） |

**書類を開いても、その隣のファイルは読めない。** 画像を表示するには
フォルダを読む許可を別にもらう必要がある（`FolderAccess`）。
一度もらえばブックマークとして保存し、次の起動時に開き直す。
