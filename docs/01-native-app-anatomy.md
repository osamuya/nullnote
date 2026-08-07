# macOS ネイティブアプリの構造

Nullnote を題材に、ソースコードが「アプリ」になるまでを追う。
数値やパスはすべてこのプロジェクトの実測値。

## 目次

1. [全体の流れ](#1-全体の流れ)
2. [`.app` はフォルダである](#2-app-はフォルダである)
3. [`Info.plist` がアプリを「アプリ」にする](#3-infoplist-がアプリをアプリにする)
4. [静的リンクと動的リンク](#4-静的リンクと動的リンク)
5. [Debug と Release で形が違う](#5-debug-と-release-で形が違う)
6. [DerivedData](#6-derivedata)
7. [署名とサンドボックス](#7-署名とサンドボックス)
8. [用語のまとめ](#8-用語のまとめ)

---

## 1. 全体の流れ

```
① .swift ファイル群
        │  swiftc（コンパイラ）
        ▼
② .o          オブジェクトファイル … 機械語の断片。単体では実行できない
   .swiftmodule                    … 「このモジュールに何があるか」の目録
        │  ld（リンカ）
        ▼
③ Mach-O 実行ファイル               … 1本の実行可能なバイナリ
        │  リソースと Info.plist を決められた形に並べる
        ▼
④ Nullnote.app                      … バンドル = 決まった構造のフォルダ
        │  codesign
        ▼
⑤ 署名済み .app                     … ここでやっと macOS が起動を許す
```

**コンパイル**（①→②）と**リンク**（②→③）は別の工程。
コンパイラは1ファイルずつ機械語に翻訳するだけで、他のファイルの関数の
「実際の番地」は知らない。それを繋ぎ合わせて1本にするのがリンカ。

このプロジェクトの中間生成物は実際にこうなっている。

```
DerivedData/…/Build/Intermediates.noindex/
├─ MarkdownCore.build/     ← ② の置き場（ターゲットごとに分かれる）
├─ NullnoteUI.build/
├─ cmark-gfm.build/        ← swift-markdown が内部で使う C ライブラリ
│                            （html.o, map.o, commonmark.o … C のコンパイル結果）
└─ Nullnote.build/
```

`Markdown.swiftmodule` `MarkdownCore.swiftmodule` などが並ぶのは、
Swift が「ヘッダファイル」の代わりにモジュール単位の目録を持つため。
`import MarkdownCore` と書いたときにコンパイラが読むのはこれ。

---

## 2. `.app` はフォルダである

macOS の肝。Finder が1個のアイコンに見せているだけで、実体はディレクトリ。
右クリック →「パッケージの内容を表示」で中に入れる。

Release ビルドの実際の中身:

```
Nullnote.app/
└─ Contents/
   ├─ Info.plist          ← アプリの身分証明書
   ├─ PkgInfo             ← 4文字のタイプコード（"APPL"）。古い時代の名残
   ├─ MacOS/
   │  └─ Nullnote         ← ③ の実行ファイル本体（4.4 MB）
   └─ _CodeSignature/
      └─ CodeResources    ← 同梱ファイル全部のハッシュ一覧（改竄検出用）
```

画像やローカライズを入れると `Contents/Resources/` が増える。
自前の dylib や framework を同梱すると `Contents/Frameworks/` が増える。
Nullnote はどちらも無いので、この最小構成になっている。

> **なぜフォルダなのか。**
> アプリの実体と、必要なリソースを1つの単位として扱えるから。
> だから macOS のアプリは「フォルダをコピーすれば入り、捨てれば消える」。
> `/Applications` に置くのは、単にこのフォルダを移動しているだけ。
> インストーラが必要になるのは、システム領域に何か置きたいときだけ。

---

## 3. `Info.plist` がアプリを「アプリ」にする

実行ファイルだけでは、ダブルクリックしても何も起きない。
OS はこのファイルを読んで、初めてそれをアプリとして扱う。

Nullnote の Info.plist に実際に入っている値:

| キー | 値 | それによって起きること |
|---|---|---|
| `CFBundleExecutable` | `Nullnote` | `Contents/MacOS/Nullnote` が起動対象になる |
| `CFBundleIdentifier` | `com.roughlang.Nullnote` | 設定の保存先・権限の管理単位が決まる |
| `CFBundlePackageType` | `APPL` | 「これはアプリケーションだ」 |
| `LSMinimumSystemVersion` | `14.0` | 古い macOS では起動を拒否される |
| `CFBundleDevelopmentRegion` | `ja` | 標準メニューが「ファイル」「編集」になる |
| `UTImportedTypeDeclarations` | `net.daringfireball.markdown` | `.md` が Nullnote に関連付く |
| `CFBundleDocumentTypes` | 上記の型 | 「このアプリで開く」の候補に出る |

**同じ実行ファイルでも Info.plist が違えば別のアプリとして振る舞う。**
`CFBundleIdentifier` を変えれば設定も権限も別扱いになる。

### 生成と手書きの合わせ技

このプロジェクトでは両方使っている。

```
GENERATE_INFOPLIST_FILE = YES        ← バージョン等は Xcode が自動で入れる
INFOPLIST_FILE = Supporting/Info.plist  ← 手書きの分をここに置く
```

Xcode は手書きの plist に、ビルド設定由来のキー（`CFBundleVersion`、
`DTPlatformName` 等）を**追記**して最終形を作る。
`UTImportedTypeDeclarations` のような配列は自動生成では書けないので、
手書きの plist が要る。

---

## 4. 静的リンクと動的リンク

`.app` の中に `MarkdownCore.framework` のようなものは**無い**。
どこへ行ったのか。

```sh
$ nm Nullnote.app/Contents/MacOS/Nullnote | grep -c "MarkdownCore\|NullnoteUI"
881
```

**実行ファイルの中に溶かし込まれている**（静的リンク）。
Swift Package は既定で静的リンクされ、リンカが `.o` を1本にまとめる。
だから 4.4 MB ある。`swift-markdown` と `cmark-gfm` も同じく中にいる。

一方、システムのものは溶かし込まれていない:

```sh
$ otool -L Nullnote.app/Contents/MacOS/Nullnote
    /System/Library/Frameworks/Foundation.framework/…/Foundation
    /System/Library/Frameworks/AppKit.framework/…/AppKit
    /System/Library/Frameworks/SwiftUI.framework/…/SwiftUI
    /usr/lib/swift/libswiftCore.dylib
    …
```

これらは**動的リンク**。起動時に OS 側の実体を借りる。
全アプリで共有されるので、Nullnote に SwiftUI 本体は入っていない。

| | 静的リンク | 動的リンク |
|---|---|---|
| 何が入るか | 実行ファイルの中身になる | 「どこにあるか」の参照だけ |
| サイズ | アプリが太る | アプリは太らない |
| 更新 | 再ビルドが要る | OS 側が差し替われば自動で反映 |
| このプロジェクトでは | 自作パッケージ、swift-markdown | AppKit, SwiftUI, Swift 標準ライブラリ |

> Swift 5 より前は標準ライブラリもアプリに同梱していた（ABI が安定していなかったため）。
> いまは OS に載っているので `/usr/lib/swift/` を借りる形になっている。

---

## 5. Debug と Release で形が違う

Debug ビルドの `Contents/MacOS/` を見ると、実行ファイルが3つある。

```
Nullnote                 ←  58 KB。ただの起動用スタブ
Nullnote.debug.dylib     ← 実際のコードはこちら
__preview.dylib          ← Xcode の SwiftUI プレビュー用
```

Xcode 16 以降の仕組みで、コードを別 dylib に切り出しておくと、
**1行直したときに再リンクする範囲が小さくて済む**（ビルドが速い）。

Release ではこの分割は無く、1本にまとまる。

```
Nullnote                 ← 4.4 MB。これだけ
```

配布されるのは Release の形。
「手元では動くのに配布したら壊れた」の原因がここに潜むことがあるので、
リリース前には必ず Release ビルドで動作確認する。

---

## 6. DerivedData

```
~/Library/Developer/Xcode/DerivedData/Nullnote-dpzeqqtshkzkmsbsdlmtghastyib/
├─ Build/Products/         完成品（Debug/ と Release/）
├─ Build/Intermediates/    中間生成物（.o, .swiftmodule）
├─ SourcePackages/         取得した swift-markdown のソース
├─ Index.noindex/          コード補完・定義ジャンプ用の索引
└─ Logs/                   ビルドログ
                                             合計 191 MB
```

`Nullnote-` の後ろのハッシュは**プロジェクトの絶対パスから計算される**。
プロジェクトを別の場所へ移すと、別のフォルダが作られる。

性格を一言でいうと**キャッシュ**。

- **プロジェクトの一部ではない**ので Git に入れない
- **丸ごと削除して構わない**。次のビルドで作り直される（時間はかかる）
- 挙動が怪しいときに消すのは定石。Xcode なら Product → Clean Build Folder（⇧⌘K）

ソースを汚さない場所に中間生成物を隔離するための仕組み、と捉えればよい。

---

## 6.5. ビルドしたアプリはどこにできるか

同じアプリの `.app` が Mac の中に複数できる。**これは正常で、問題ではない。**
それぞれ役割が違うだけ。

| パス | 作られる操作 | 用途 |
|---|---|---|
| `~/Library/Developer/Xcode/DerivedData/<プロジェクト>-<ハッシュ>/Build/Products/Debug/<アプリ>.app` | Xcode の ⌘R、`xcodebuild -configuration Debug` | 開発中の動作確認 |
| `…/Build/Products/Release/<アプリ>.app` | `xcodebuild -configuration Release` | 配布用の設定でのビルド |
| `/Applications/<アプリ>.app` | 手でコピー、`install.sh` | 日常的に使う |
| `~/Library/Developer/Xcode/Archives/<日付>/<名前>.xcarchive/Products/Applications/<アプリ>.app` | Product → Archive | App Store 申請用 |

**同時にはできない。** それぞれ別の操作で作られ、同じ場所は上書きされる。
Debug ビルドを100回しても `Debug/<アプリ>.app` は1個のまま。

`/Applications` のものだけは Xcode が作らない。誰かがコピーして初めて存在する。

### Bundle ID が同じことの意味

これらはすべて同じ `CFBundleIdentifier` を持つ。macOS はこれでアプリを識別するので、
**設定とサンドボックスのコンテナを共有する**。

```
~/Library/Containers/<Bundle ID>/
```

開発ビルドで設定を変えると、`/Applications` のアプリにも反映される。
**開発中はむしろ好都合**（実際の設定のまま確認できる）。
分けたければ Debug の `PRODUCT_BUNDLE_IDENTIFIER` に `.debug` を付ける。
急いでやる必要はない。

### 唯一気をつけること

**ビルドし直したら、アプリを再起動する。**

複数の場所にビルドがあること自体は無害だが、
「直したはずなのに変わらない」の原因はほぼこれ。
起動しっぱなしのプロセスは、いつビルドされたコードを動かしているか分からない。

```sh
# いま動いているのは、いつビルドされたものか
ps -o lstart= -p $(pgrep -f "<アプリ>.app/Contents/MacOS/<アプリ>" | head -1)
stat -f "%Sm" <アプリのパス>/Contents/MacOS/<アプリ>
```

プロセスの開始時刻がビルド時刻より**前**なら、古いコードを見ている。

> **調べるときの落とし穴**: 起動テストを連続で回すと、
> 前のプロセスが終了しきる前に `pgrep` してしまい、古い方を「いま動いている」と誤読する。
> 必ず `pgrep` で 0 件になるのを確認してから次を測ること。

## 7. 署名とサンドボックス

### 署名

```sh
$ codesign -dv Nullnote.app
Identifier=com.roughlang.Nullnote
Signature=adhoc
TeamIdentifier=not set
```

`adhoc` は**このマシンでしか動かない**署名。開発中はこれで十分。
配布するには Developer ID（直接配布）か App Store の証明書が要る。

`_CodeSignature/CodeResources` に同梱ファイル全部のハッシュが入っていて、
1バイトでも書き換えると署名が壊れて起動できなくなる。

> **注意**: 開発用の署名には `com.apple.security.get-task-allow` が付く。
> デバッガを繋ぐための権限で、**配布用のビルドに残っていると審査で弾かれる**。

### サンドボックス

`Supporting/Nullnote.entitlements` に書いた権限が、署名時にバイナリへ埋め込まれる。

```sh
$ codesign -d --entitlements :- Nullnote.app
com.apple.security.app-sandbox
com.apple.security.files.user-selected.read-write
```

これにより Nullnote は:

- **ユーザーが開いた／保存したファイルにしか触れない**
- 設定やキャッシュは専用のコンテナに隔離される

```
~/Library/Containers/com.roughlang.Nullnote/
└─ Data/Library/Preferences/com.roughlang.Nullnote.plist   ← @AppStorage の保存先
```

`@AppStorage("editorFontSize")` が書き込むのはここ。
アプリを消すときはこのコンテナごと消せばきれいになる。

サンドボックスは App Store 配布の必須要件なので、**最初から有効にしておく**。
後から有効にすると、それまで通っていたファイルアクセスが軒並み止まって直すのが大変になる。

---

## 8. 用語のまとめ

| 用語 | 意味 |
|---|---|
| **Mach-O** | Apple プラットフォームの実行ファイル形式（Linux の ELF、Windows の PE にあたる） |
| **バンドル** | 決まった構造を持つフォルダを、1つの単位として扱う仕組み。`.app` `.framework` など |
| **オブジェクトファイル（.o）** | コンパイル結果の機械語の断片。まだ他と繋がっていない |
| **リンカ** | `.o` を繋ぎ合わせて実行ファイルを作るプログラム |
| **静的リンク** | ライブラリを実行ファイルの中に取り込む |
| **動的リンク** | 実行時に外のライブラリを借りる |
| **dylib** | 動的ライブラリ（Linux の .so にあたる） |
| **UTType** | ファイル形式の識別子。`public.plain-text` など逆ドメイン形式 |
| **entitlements** | アプリに許す権限の一覧。署名時にバイナリへ埋め込まれる |
| **DerivedData** | Xcode のビルドキャッシュ置き場 |

---

## 関連

- このプロジェクトの構成と設計 → [`../README.md`](../README.md)
- macOS ターゲットの設定 → [`../Apps/Nullnote-macOS/README.md`](../Apps/Nullnote-macOS/README.md)
- なぜその作りにしたか → [`02-decision-log.md`](02-decision-log.md)
