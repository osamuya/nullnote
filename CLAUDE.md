# このリポジトリでの決まり

**ここには変わらないことだけを書く。** いま何版を出しているか、どのブランチか、
何が残っているかといった**動く情報はここに置かない**。古くなったまま断定形で
残り、読む側が毎回「どこが古いか」を判定する羽目になるため。

動く情報の置き場所:

| 知りたいこと | 見るところ |
|---|---|
| いまの版・出す段取り・公開の経緯 | `docs/03-release-plan.md` |
| 残っている要望と不具合 | `docs/運用上の修正点・改良点.md` |
| 版の番号そのもの | `Apps/Nullnote-macOS/Version.xcconfig` |

**着手する前に `docs/運用上の修正点・改良点.md` を読むこと。**

## `.md` を書き換えるときは `mdmerge` を通す

**このリポジトリの文書は、利用者と Claude Code が代わる代わる直す。**
Nullnote で開いたまま直されていることがあり、素直に上書きすると相手の直しが黙って消える
（実際に消した。理由と実測は `docs/02-decision-log.md` の D-34）。

アプリ側の合流はメモリ上の編集画面が相手なので、**外から書く側は守ってもらえない**。
基準を持てるのはこちらだけ。手順はこう。

```sh
# 1. 読む前に控えを取る（これが base になる）
cp docs/対象.md /tmp/base.md

# 2. 直した結果を別ファイルに書く（/tmp/ours.md）

# 3. 書く直前のディスクと突き合わせて書く
Tools/mdmerge/.build/debug/mdmerge --base /tmp/base.md --ours /tmp/ours.md docs/対象.md
```

- 終了コード **0**: 印なしで書けた
- 終了コード **1**: 同じ場所を直していたので `<<<<<<< 自分の更新` の印を入れた。
  **どちらを残すかは利用者が決める。** 印の中身をそのまま見せて聞くこと。
  自分の版を採って勝手に片付けない（実際にそれで利用者の1行を消した）。
  印を残したまま次の作業に移らないこと

道具が無ければ `cd Tools/mdmerge && swift build` で作る。

**行を丸ごと置き換えない。** 相手が同じ行に書き足しているとき、行ごと差し替えると
合流しようがなくなる。直したい部分だけを最小限で書き換える。

## 確認の走らせ方

```sh
cd Packages/MarkdownCore && swift test
cd Packages/NullnoteUI   && swift test
cd Tools/mdmerge         && swift test
cd Apps/Nullnote-macOS   && xcodebuild -scheme Nullnote -configuration Debug build
```

`Packages/` を直したら、**iOS 向けにも通す**（版を出す前は必ず）。
`#if canImport(AppKit)` の入れ違いは macOS 側では何も言わない。1.1 で実際に踏んだ（D-61）。

```sh
cd Packages/MarkdownCore && xcodebuild -scheme MarkdownCore -destination 'generic/platform=iOS' build
cd Packages/NullnoteUI   && xcodebuild -scheme NullnoteUI   -destination 'generic/platform=iOS' build
```

画面の見え方を確かめるときは、`NSHostingView` をウインドウに載せてランループを回してから
`cacheDisplay(in:to:)` する（`ImageRenderer` では `task` が走らない。B-3）。

アプリの中で何が起きたかを見るときは足あとを出す。

```sh
open -a /Applications/Nullnote.app --env NULLNOTE_TRACE=1 --stderr /tmp/nullnote-trace.log <ファイル>
```

**Debug と Release は Bundle ID が別**（`com.sabanote.Nullnote.debug` / `com.sabanote.Nullnote`）。
`run.sh` の開発版と `/Applications` の普段使いは**別のアプリ**で、同時に動かしてよい。
`run.sh` は Debug 版だけを止め、最後に「✅ いまビルドしたものが動いています」と出す。
設定とフォルダの許可も別なので、**普段使いを壊さずに初期状態から試せる**（D-46）。

```sh
rm -rf ~/Library/Containers/com.sabanote.Nullnote.debug/Data   # 開発版だけ戻す
```

**`open -a` は、すでに動いているアプリを起動し直さない。** ファイルを渡すだけなので、
`--env` も効かない。**測る前に止め、止まったことを目で見る。**
動いているプロセスは、消した設定をまだ手の中に持っている（フォルダの許可は
起動時に復元され、プロセスが生きているあいだ有効なまま）。実際にこれで2度誤った。
手順は README の「動きを確かめる」。

**止めるときはパスまで指す。**

```sh
# 何が動いているかを先に見る
ps -eo pid,lstart,command | grep "MacOS/Nullnote" | grep -v grep
# Debug 版だけを止める
pkill -f "Products/Debug/Nullnote.app/Contents/MacOS/Nullnote"
```

**`pkill -f "MacOS/Nullnote"` と書いてはいけない。普段使いの `/Applications` 版まで落ちる。**
2026-09-09 に実際に落とし、利用者が開いていた窓を消した。
書類の中身は自動保存で残るが、**macOS に窓の記憶が無ければ開き直しになる。**

**きれいに終了させたいときは `osascript` を使う。** `pkill` で落とすと
macOS が窓の記憶を残し、次の起動で前回の書類を全部開き直す（D-52）。

```sh
osascript -e 'tell application id "com.sabanote.Nullnote.debug" to quit'
```

**`tell application "Nullnote"` と名前で書くと、同名のアプリの片方にしか届かない。**
`System Events` の `process "Nullnote"` も同じで、名前では1つにしか解決されない。
プロセス番号か Bundle ID で指すこと（D-53）。

## 書きもの

`docs/` は**手元にだけ置く開発資料**で、公開リポジトリには含めていない（`.gitignore`）。
ソースのコメントに出てくる `D-24` のような番号は、この中の判断の記録を指す。

- 判断は `docs/02-decision-log.md` に D-番号 で足す（新しいものが上）。
  **捨てた案とその理由まで書く。**
- 要望と不具合は `docs/運用上の修正点・改良点.md`。終わったら「終了」へ移し、
  取り消し線を引いて D-番号 を添える
- リポジトリ全体の構成は `docs/00-repository-guide.md`
