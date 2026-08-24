# このリポジトリでの決まり

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

画面の見え方を確かめるときは、`NSHostingView` をウインドウに載せてランループを回してから
`cacheDisplay(in:to:)` する（`ImageRenderer` では `task` が走らない。B-3）。

アプリの中で何が起きたかを見るときは足あとを出す。

```sh
open -a /Applications/Nullnote.app --env NULLNOTE_TRACE=1 --stderr /tmp/nullnote-trace.log <ファイル>
```

## 書きもの

- 判断は `docs/02-decision-log.md` に D-番号 で足す（新しいものが上）。
  **捨てた案とその理由まで書く。**
- 要望と不具合は `docs/運用上の修正点・改良点.md`。終わったら「終了」へ移し、
  取り消し線を引いて D-番号 を添える
