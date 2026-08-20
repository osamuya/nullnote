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
| アプリアイコン | あり（2026-08-20 に正式版へ差し替え） | 元絵は `sabanote_site/design/nullnote/` |

アプリの実体は DerivedData の中にあり、Clean Build Folder で消える。

---

## 第1段階: ローカルで常用できるようにする

### T1-1. アプリアイコンを用意する 〔済み〕

2026-08-20 に正式版へ差し替えた。元絵は
`/Users/osamu-yamakami/Develop/sabanote/sabanote_site/design/nullnote/nullnote_icon_dark1_sq.png`
（1024×1024、角の立った正方形）。

差し替えるときは元絵を渡すだけでよい。

```sh
cd Apps/Nullnote-macOS
./make-icons.py <元絵.png>   # 角丸を当てて7サイズを生成
./install.sh
```

**角丸はスクリプト側で当てる。** 1024 の画布に 824 の角丸四角（半径 22.4%）。
元絵に焼き込んでもらう必要は無い。

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

#### T2-1. Apple Developer Program に登録する 〔あなたのみ〕〔いまここ〕

**Individual（個人）として新規登録する。** 同じ Apple ID のままでよい。

- [developer.apple.com/programs/enroll/](https://developer.apple.com/programs/enroll/)
- 年額 99 USD。Apple ID に**二要素認証**が要る
- 本人確認は `Apple Developer` アプリ（Mac App Store で無料）から身分証を送る形になることが多い
- 有効化まで **24〜48時間**程度
- 登録後に Team ID（10桁）が分かる → `DEVELOPMENT_TEAM` に設定する

**法人（Organization）で登録しない。** D-U-N-S 番号が要り、数日〜数週間かかる。

**Individual の販売者名は法的な氏名になる。** 屋号（`roughlang`）を
App Store の販売者欄に出したい場合は種別から検討が要る。
`NSHumanReadableCopyright` は自由文なので、そちらは屋号でも書ける。

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

#### T2-4. 署名設定を切り替える 〔私〕〔済み〕

```
CODE_SIGN_IDENTITY = "Apple Development"    ← "-" から変更
DEVELOPMENT_TEAM = 542DBL2NGA               ← 新規設定
CODE_SIGN_STYLE = Automatic                 ← 変更なし
```

**`Apple Distribution` を直接書かない。** 自動署名では、ふだんのビルドは
`Apple Development` で行い、**配布用の証明書はアーカイブを書き出すときに選ぶ**
（`ExportOptions.plist` の `method`）。設定に焼き込むと、開発ビルドまで
配布用証明書を要求するようになる。

**同名のチームが2つ並んでいても、`DEVELOPMENT_TEAM` に ID を書けば取り違えない。**
Xcode は名前ではなく ID で選ぶ。

**`xcodebuild` は自分で証明書を作らない。** `-allowProvisioningUpdates` を
付けたときだけ作る。付けずに走らせると
`No "Mac Development" signing certificate matching team ID ... was found` で止まる。

**確認すること**: 配布ビルドに `com.apple.security.get-task-allow` が
残っていないこと（デバッガ接続用の権限。残っていると審査で弾かれる）。

```sh
codesign -d --entitlements :- /path/to/Nullnote.app
```

### 素材の準備

#### T2-5. アプリアイコンを仕上げる 〔済み〕

T1-1 で差し替え済み。`icon_1024.png` が申請用のマスターになる。

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

- 解析・トラッキングなし
- サーバーへの送信なし。**アカウントも無い**
- 保存するのは書類ファイルと設定4つ（`editorAppearance` / `editorFontSize` /
  `editorShowsLineNumbers` / `syncsTitleWithFileName`）と、
  フォルダを読む許可のブックマークのみ。すべてローカル
- ネットワークは **`network.client` が有効**。ただし通信するのは、
  利用者が本文に自分で書いた `https://` の画像を読むときだけ（D-26）

→ App Store Connect では「データを収集しない」を選ぶ。
画像の読み込みは利用者が書いた URL を開くだけで、こちらは何も集めない。

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

## 作業ログ

実際に何が起きたかを、日付つきで残す。来年の更新や、2台目の Mac で
証明書を作り直すときに効く。

| 日付 | やったこと | 結果・つまずき |
|---|---|---|
| 2026-08-08 | 署名まわりの棚卸し | 証明書0件、プロファイル無し、Xcode にアカウント未登録 |
| 2026-08-20 | アイコンを正式版に差し替え | T1-1 完了。作り直しは `make-icons.py`（D-31） |
| 2026-08-20 | Developer アカウントの状態を確認 | **自分名義のメンバーシップは無かった。** Apple ID は ROYAL COSMETICS CO., LTD. のチームに所属しているが、Nullnote とは無関係の別チーム。会社チームからは個人の配布はできない |
| 2026-08-20 | 署名の材料を再確認 | 期限切れの証明書すら1枚も無い。まっさらな状態 |
| 2026-08-20 | Apple ID 側の準備 | 氏名（`Osamu` / `Yamakami`）・2ファクタ認証とも確認済み。使う Apple ID は iCloud と同じもの |
| 2026-08-20 | Apple Developer アプリから登録を試行 | **失敗。**「現在、このアイテムはお住まいの国／地域で利用できません」。価格表示が **¥12,800 → $98.99** とドル建てに変わっており、**App Store アカウントの国／地域が日本でない**疑いが濃い（アプリ経由の購入は App Store のサブスクとして処理されるため） |
| 2026-08-20 | Web から登録を試行 | **失敗。**「リクエストを処理できません。不明なエラーが発生しました」。アプリ側で発行された登録ID が処理中で競合している可能性 |
| 2026-08-20 | Web の登録画面をリロード | **同じ登録IDで再開できた。** 入力済みの情報はサーバー側に残っていた。料金表示も **¥12,980（円建て）** に戻り、国／地域の問題は起きなかった |
| 2026-08-20 | 決済完了 | Individual として登録。有効化待ち（確認メールは24時間以内） |
| 2026-08-20 | 申請用の設定を整備 | `MARKETING_VERSION` を `1.0` に。`NSHumanReadableCopyright` と `ITSAppUsesNonExemptEncryption = NO` を追加 |
| 2026-08-20 | メンバーシップ有効化 | Team ID `542DBL2NGA`（Individual）|
| 2026-08-20 | 署名設定を切り替え（T2-4） | `CODE_SIGN_IDENTITY` を `-` から `Apple Development` に。`DEVELOPMENT_TEAM = 542DBL2NGA` を追加。Debug / Release とも `TeamIdentifier=542DBL2NGA` で署名されることを確認 |
| 2026-08-20 | 開発用証明書を作成 | `Apple Development: Osamu Yamakami (GAYKK44Y47)`。`xcodebuild` に `-allowProvisioningUpdates` を付けると自動で作られた |
| 2026-08-20 | 公証の認証情報を用意 | アプリ用パスワードを作り、`notarytool store-credentials` でキーチェーンに `nullnote-notary` として保存 |
| 2026-08-20 | Developer ID 版を書き出し | `Developer ID Application: Osamu Yamakami (542DBL2NGA)` で署名。**`get-task-allow` は書き出しで自動的に外れた** |
| 2026-08-20 | アプリを公証・ステープル | Accepted。`spctl` が `source=Notarized Developer ID` を返す |
| 2026-08-20 | DMG を作成（1回目） | **判定 `rejected（no usable signature）`。** 公証は通るが、**DMG 自体が未署名**だと Gatekeeper が受け付けない |
| 2026-08-20 | Developer ID 証明書をローカルに作成 | Xcode → Manage Certificates… → 「+ ⌄」→ Developer ID Application。書き出し時のクラウド署名では `codesign` から使えないため |
| 2026-08-20 | DMG を署名して公証・ステープル | **判定 `accepted`。配布可能な `Nullnote-1.0.dmg`（2.1 MB）ができた** |
| 2026-08-20 | 手順をスクリプト化 | `Apps/Nullnote-macOS/release-dmg.sh`。事前確認から判定まで一気に通す |

**次にやること**: DMG の配布先（サイト）を用意する。
そのあと App Store 版（Apple Distribution 証明書、App Store Connect でのアプリ登録、
掲載文、スクリーンショット、審査）と iOS 版へ。

### 分かったこと

**1つの Apple ID は複数のチームに所属できる。**
会社チームのメンバーであることと、自分名義のメンバーシップを持っていることは別物。
アカウントページ右上のチーム切り替えメニューに自分の名前が出なければ、
個人メンバーシップは無い。

**DMG は、中のアプリだけ署名・公証しても配れない。**
**DMG 自体にも署名と公証が要る。** 未署名の DMG は公証には通るが、
`spctl` が `rejected（no usable signature）` を返す。実測で確かめた。

**署名し直すとステープルは無効になる。**
DMG は「作り直す → 署名 → 公証 → ステープル」の順に固定する。

**書き出し時のクラウド署名では、`codesign` から証明書を使えない。**
Xcode は Developer ID 証明書をクラウドで管理して書き出しに使うが、
キーチェーンには残らない（`security find-identity` に出てこない）。
DMG に自分で署名するには、**Manage Certificates… から明示的に作る**必要がある。

**Apple Developer アプリからの購入は、App Store のサブスクとして処理される。**
そのため **App Store アカウントの国／地域**に引きずられる。価格がドル建てで出たら、
国／地域が日本になっていない合図。**Web からの登録はクレジットカードで直接決済する**ので、
この影響を受けない。日本で登録するなら Web 経由のほうが確実。

**登録の途中でエラーが出ても、入力は消えていないことがある。**
「リクエストを処理できません」のあとリロードしたら、同じ登録IDで続きから再開できた。
**「登録をキャンセルする」を押す前に、まずリロードして確かめる。**

**Apple のアカウントページは左メニューではなくなった。**
上部のアイコン列（プログラムのリソース／プロフィール／**メンバーシップの詳細**／…）が
いまのナビゲーション。古い手順書の「左メニューの Membership」は読み替える。

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

**2026-08-20 に見直した。** 「アカウント所持済み」と書いていたが、
**自分名義のメンバーシップは無かった**（下の作業ログを参照）。

この Mac には署名の材料が何も無い。

```sh
security find-identity -v -p codesigning   # → 0 valid identities found
security find-identity -v                  # → 0（期限切れの証明書すら無い）
ls ~/Library/Developer/Xcode/UserData/Provisioning\ Profiles/   # → ディレクトリ自体が無い
defaults read com.apple.dt.Xcode DVTDeveloperAccountManagerAppleIDLists  # → 未設定
```

証明書は Mac ごとに作るものなので、これ自体は異常ではない。
ただし**作るには先に有料メンバーシップが要る**。

### アプリ側の棚卸し

| 項目 | 状態 |
|---|---|
| Bundle ID `com.roughlang.Nullnote` | ✅ |
| `LSApplicationCategoryType = public.app-category.productivity` | ✅ |
| `LSMinimumSystemVersion = 14.0` | ✅ |
| アプリアイコン（16〜1024） | ✅ |
| `MARKETING_VERSION = 1.0` / `CURRENT_PROJECT_VERSION = 1` | ✅ |
| `NSHumanReadableCopyright = © 2026 Osamu Yamakami` | ✅ |
| `ITSAppUsesNonExemptEncryption = NO` | ✅ |
| 署名 | ✅ `TeamIdentifier=542DBL2NGA`（開発用証明書） |
| `com.apple.security.get-task-allow` | ⚠️ 開発用署名なので入っている。**配布用に書き出すと外れる。書き出し後に必ず確認する** |

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
