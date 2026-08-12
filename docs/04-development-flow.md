# 開発の手順

コードを直してから、常用アプリに反映するまでの流れ。

```
コードを直す
    ↓
swift test          速い。ここで落ちたら先に進まない
    ↓
./run.sh            実際に触って確認
    ↓
（詰まったら Xcode で ⌘R）  ブレークポイントを置ける
    ↓
./install.sh        /Applications に反映
```

## どこを直すか

| 直す内容 | 場所 |
|---|---|
| Markdown の解析、対応記法 | `Packages/MarkdownCore/` |
| 配色、ハイライト、エディタ、プレビュー | `Packages/NullnoteUI/` |
| メニュー、設定画面、書類の読み書き | `Apps/Nullnote-macOS/Nullnote/` |

`Apps/Nullnote-macOS/Nullnote/` はファイル同期グループなので、
**`.swift` を置くだけでターゲットに入る**。Xcode 側の操作は要らない。

## テスト

```sh
cd /Users/osamu-yamakami/Develop/macapp/MacApp/MarkdownEditor

swift test --package-path Packages/MarkdownCore    # 72件
swift test --package-path Packages/NullnoteUI      # 197件
```

`Packages/` を直したときは、アプリを起動する前にこれを通す。
ビルドより速く終わるので、間違いに早く気づける。

iOS 側を壊していないかの確認:

```sh
cd Packages/MarkdownCore && xcodebuild -scheme MarkdownCore -destination 'generic/platform=iOS' build
cd Packages/NullnoteUI   && xcodebuild -scheme NullnoteUI   -destination 'generic/platform=iOS' build
```

## 動かす

```sh
cd Apps/Nullnote-macOS
./run.sh ~/Desktop/Sample.md     # ファイルを開いて起動
./run.sh                         # 新規書類で起動
```

やっていることは3つ。

1. Debug ビルド
2. 起動中のアプリを終了（**終了しきるまで待つ**）
3. ビルドしたものを起動

最後に判定が出る。

```
    ✅ いまビルドしたものが動いています
```

これが出れば、見ているのは直したコード。

### 手で打つ場合

```sh
cd Apps/Nullnote-macOS
xcodebuild -scheme Nullnote -configuration Debug build
osascript -e 'tell application "Nullnote" to quit'     # ← 飛ばさない
open -a "$(xcodebuild -scheme Nullnote -configuration Debug -showBuildSettings 2>/dev/null \
           | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)/Nullnote.app" ~/Desktop/Sample.md
```

**終了の手順を飛ばさないこと。** 起動しっぱなしのプロセスは古いコードを動かし続ける。

### Xcode から

```sh
open Apps/Nullnote-macOS/Nullnote.xcodeproj
```

⌘R でビルドと起動。Xcode は起動中のものを自動で終了させるので取り違えが起きない。
ブレークポイントで止めて変数を見られるので、**原因が分からないときはこちら**。

## 常用アプリに反映する

```sh
cd Apps/Nullnote-macOS
./install.sh
```

Release ビルド → 起動中なら終了 → `/Applications/Nullnote.app` へコピー。

## 「直したのに変わらない」とき

まずこれを疑う。原因のほとんどは**古いプロセスが動いたまま**。

```sh
# いま動いているのはいつ起動したものか
ps -o lstart= -p $(pgrep -f "Nullnote.app/Contents/MacOS/Nullnote" | head -1)

# コードがいつ更新されたか
stat -f "%Sm" /Applications/Nullnote.app/Contents/MacOS/Nullnote
```

プロセスの開始がコードの更新より**前**なら、古いものを見ている。終了して開き直す。

`./run.sh` を使えばこの確認は自動で入る。

> **調べるときの落とし穴**: 起動テストを続けて回すと、
> 前のプロセスが終了しきる前に `pgrep` して古い方を掴む。
> 必ず `pgrep` が 0 件になるのを待ってから測ること。

### `open` が `-600` で失敗する

```
_LSOpenURLsWithCompletionHandler() failed ... with error -600.
```

`-600` は procNotFound。**強制終了（`pkill`）した直後に `open` すると出る。**
プロセスはもう無いのに、LaunchServices の側がまだ「起動中」と思っている。

少し待って開き直せば起動する。`run.sh` は、プロセスが消えるのを待ったうえで
`open` を最大10回まで再試行するようにしてある。

そもそも強制終了に至る原因は、**同名のアプリが2つ動いていること**。
`osascript -e 'tell application "Nullnote" to quit'` は名前で1つに解決されるので、
DerivedData のものと `/Applications` のものが両方動いていると片方しか終了しない。
残った方が `pgrep` に引っかかり続けて、待ち時間切れ → 強制終了、という順で起きる。

## 関連

- `.app` がどこにできるか、なぜ複数あるか → [01-native-app-anatomy.md](01-native-app-anatomy.md) の「6.5」
- リリースまでの段取り → [03-release-plan.md](03-release-plan.md)
