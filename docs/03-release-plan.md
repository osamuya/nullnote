# リリース計画

**第1段階**でローカル常用できる状態にし、**第2段階**で App Store へ出す。
先に常用して不便を洗い出す方が、審査のやり直しが減る。

## 現状（起点）

| 項目 | 値 | 備考 |
|---|---|---|
| Bundle Identifier | `com.roughlang.Nullnote` | 確定 |
| 最低 OS | macOS 14.0 | |
| `MARKETING_VERSION` | `0.1` | 公開前に決め直す |
| `CURRENT_PROJECT_VERSION` | `1` | ビルド番号。申請ごとに増やす |
| 署名 | `CODE_SIGN_IDENTITY = "-"`（アドホック） | この Mac でのみ動く |
| `DEVELOPMENT_TEAM` | 未設定 | Developer Program 登録後に設定 |
| ハードンドランタイム | 有効 | そのままでよい |
| サンドボックス | 有効 | そのままでよい |
| アプリアイコン | **無し** | 要作成 |

アプリの実体は DerivedData の中にあり、Clean Build Folder で消える。

---

## 第1段階: ローカルで常用できるようにする

### T1-1. アプリアイコンを用意する 〔要: 元絵〕

- 1024×1024 の元絵を用意する（PNG、余白込みの macOS 標準の角丸で描く）
- 各サイズを生成してアセットカタログに入れる
- 元絵さえあれば、サイズ生成と組み込みは自動化できる

**いま無いと何が起きるか**: Dock と Finder で汎用の書類アイコンになる。
App Store 申請では**必須**なので、どのみち第2段階までに要る。

### T1-2. バージョン番号を決める

`0.1` のまま常用しても支障はないが、App Store に出すなら `1.0` から始めるのが素直。
第2段階の直前で決めればよい。

### T1-3. Release ビルドを `/Applications` に置く

```sh
cd Apps/Nullnote-macOS
xcodebuild -scheme Nullnote -configuration Release build
cp -R "$(xcodebuild -scheme Nullnote -configuration Release -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/Nullnote.app" /Applications/
```

アドホック署名のままでも、この Mac では問題なく起動する。
以降は `open -a Nullnote ファイル.md` で開ける。Launchpad にも出る。

**注意**: 更新するたびにコピーし直す必要がある。手順をスクリプトにしておくとよい。

### T1-4. 常用して不便を洗い出す 〔あなた〕

ここが第1段階の本体。使ってみて出てきたものを次の作業の入口にする。
既に候補として挙がっているもの:

- 記法の入力補助（⌘B で `**` を挿入、リストの継続入力）
- コードブロックのシンタックスハイライト（言語名は既にトークンとして取れている）
- 記法文字（`marker`）の濃さ調整（ライトで 2.13:1 とやや薄い）

---

## 第2段階: App Store 公開

### 先に着手すべきもの（待ち時間がある）

#### T2-1. Apple Developer Program に登録する 〔あなたのみ〕

- 年額 99 USD
- **審査に数日〜1週間かかる**ので、第1段階と並行して先に出しておく
- 登録後に Team ID が分かる → `DEVELOPMENT_TEAM` に設定する

#### T2-2. 名称・商標・ドメインを確認する 〔あなたのみ〕

| 確認先 | 目的 |
|---|---|
| App Store で「Nullnote」を検索 | 同名アプリの有無 |
| 特許庁 J-PlatPat | 日本の商標 |
| USPTO | 米国の商標 |
| ドメインの空き | サポート URL とプライバシーポリシー URL に必要 |

**ドメインは実質必須**。App Store Connect でサポート URL の入力を求められる。

### 署名とビルドの切り替え

#### T2-3. Bundle ID を Developer Portal に登録する 〔あなたのみ〕

`com.roughlang.Nullnote` を Identifiers に登録。App Sandbox を capability として有効にする。

#### T2-4. 署名設定を切り替える 〔私〕

```
CODE_SIGN_IDENTITY = "Apple Distribution"   ← "-" から変更
DEVELOPMENT_TEAM = <Team ID>                ← 新規設定
CODE_SIGN_STYLE = Automatic
```

**確認すること**: 配布ビルドに `com.apple.security.get-task-allow` が
残っていないこと（デバッガ接続用の権限。残っていると審査で弾かれる）。

```sh
codesign -d --entitlements :- /path/to/Nullnote.app
```

### 素材の準備

#### T2-5. アプリアイコンを仕上げる 〔元絵をいただければ私〕

T1-1 と同じもの。1024×1024 が申請用のマスターになる。

#### T2-6. スクリーンショットを用意する 〔私〕

macOS 版の規定サイズ（いずれか）:

- 1280×800
- 1440×900
- 2560×1600
- 2880×1800

最低1枚、最大10枚。ライト／ダーク、エディタ単独／プレビュー並列を見せたい。

**この環境では画面収録の権限が無い**ため、`screencapture` は使えない。
ビューをオフスクリーンで描いて PNG に焼く方法で作る
（`docs/02-decision-log.md` の「検証方法についての記録」を参照）。

#### T2-7. 掲載文を書く 〔一緒に〕

- アプリ名、サブタイトル（30文字）
- 説明文（4000文字まで）
- キーワード（100文字、カンマ区切り）
- カテゴリ: 仕事効率化（`public.app-category.productivity` を既に設定済み）
- サポート URL、プライバシーポリシー URL

### 申告

#### T2-8. App Privacy を申告する 〔私が整理、入力はあなた〕

**このアプリはデータを一切収集しない。**

- ネットワーク通信なし
- 解析・トラッキングなし
- 保存するのは書類ファイルと設定2つ（`editorAppearance` / `editorFontSize`）のみで、
  すべてローカル

→ App Store Connect では「データを収集しない」を選ぶだけで済む。

#### T2-9. Export Compliance に答える 〔あなた〕

暗号化は使っていない。`ITSAppUsesNonExemptEncryption = NO` を Info.plist に
入れておくと、申請のたびに聞かれずに済む。

### 提出

#### T2-10. アーカイブして検証・アップロードする 〔私がコマンド化〕

```sh
xcodebuild -scheme Nullnote -configuration Release \
           -archivePath build/Nullnote.xcarchive archive
xcodebuild -exportArchive -archivePath build/Nullnote.xcarchive \
           -exportOptionsPlist ExportOptions.plist -exportPath build/export
xcrun altool --validate-app -f build/export/Nullnote.pkg -t macos ...
```

`ExportOptions.plist` は Team ID が決まってから作る。

#### T2-11. 審査に出す 〔あなた〕

初回は 1〜3 日程度。リジェクトされたら理由を見て直す。

---

## 分担の整理

| 私ができること | あなたにしかできないこと |
|---|---|
| アイコンの各サイズ生成と組み込み | Developer Program 登録 |
| 署名設定の切り替え | 証明書・プロビジョニングの作成 |
| スクリーンショットの生成 | App Store Connect でのアプリ登録・申請 |
| App Privacy / Export Compliance の内容整理 | 名称・商標・ドメインの確認 |
| アーカイブとバリデーションのコマンド化 | 掲載文の最終決定 |
| 掲載文の下書き | 審査への応答 |

## 次回の入口

第1段階（ローカル常用）は完了。**第2段階の入口に立っている。**

### 分かっていること（2026-08-08 時点で実機を調べた結果）

Apple Developer Program のアカウントは**所持済み**。
ただしこの Mac には署名の材料が何も無い。

```sh
security find-identity -v -p codesigning   # → 0 valid identities found
ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/   # → 空
defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists  # → 未設定
```

証明書は Mac ごとに作るものなので、これは異常ではない。Xcode にアカウントを
追加すれば作られる。

### アプリ側の棚卸し

| 項目 | 状態 |
|---|---|
| Bundle ID `com.roughlang.Nullnote` | ✅ |
| `LSApplicationCategoryType = public.app-category.productivity` | ✅ |
| `LSMinimumSystemVersion = 14.0` | ✅ |
| アプリアイコン（16〜1024） | ✅ |
| `MARKETING_VERSION = 0.1` / `CURRENT_PROJECT_VERSION = 1` | ⚠️ 公開前に決め直す（`1.0` / `1` を提案） |
| `NSHumanReadableCopyright` | ❌ 空 |
| `ITSAppUsesNonExemptEncryption` | ❌ 未設定。入れておくと申請ごとの質問を省ける |
| 署名 | ❌ `Signature=adhoc` / `TeamIdentifier=not set` |
| `com.apple.security.get-task-allow` | ⚠️ **入っている。Release からは必ず外す**（審査で弾かれる） |

確認に使ったコマンド:

```sh
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" /Applications/Nullnote.app/Contents/Info.plist
codesign -dv --entitlements - /Applications/Nullnote.app
```

### 最初の一手（利用者にしかできない）

Xcode にアカウントを追加し、**Team 名と Team ID を控える**。

```
Xcode → Settings… → Accounts → ＋ → Apple ID → サインイン
```

年会費の有効期限も併せて確認する（切れているとアップロードできない）。

### Team ID が分かってから、こちらで進めること

1. `DEVELOPMENT_TEAM` を設定し、署名をアドホックから Apple Distribution へ
2. `get-task-allow` を Release ビルドから外す（Debug には残す）
3. `NSHumanReadableCopyright` と `ITSAppUsesNonExemptEncryption` を Info.plist へ
4. バージョンを `1.0` / ビルド `1` に
5. アーカイブとバリデーションのコマンド化

### 並行して進められること（Team ID を待たない）

- App Store で「Nullnote」の同名アプリを検索
- サポート URL とプライバシーポリシー URL に使うドメインを決める
- 掲載文の下書き、スクリーンショットの生成
