#!/bin/sh
#
# App Store 用の元画像を撮る。窓を1枚ずつ、影なしで。
#
#   ./capture-shots.sh
#
# 撮ったものは AppStore/src/ に入る。そのあと:
#
#   ./make-appstore-shots.py AppStore/src/*.png
#
# ## 事前に
#
# **画面収録の許可**が要る。
# システム設定 → プライバシーとセキュリティ → 画面収録 → ターミナルを許可
# → **ターミナルを再起動**（再起動しないと効かない）
#
# ## 撮り方
#
# 1枚ごとに「窓をクリックしてください」と出る。Nullnote の窓をクリックすると撮れる。
# **Retina のまま撮れる**ので、あとで引き伸ばす必要が無い。
#
# 撮り直したいときは、その番号のファイルを消してもう一度走らせる。
# 既にあるファイルは飛ばす。
set -eu
cd "$(dirname "$0")"
SRC=AppStore/src
mkdir -p "$SRC"

shoot() {
    name="$1"; setup="$2"
    if [ -f "$SRC/$name.png" ]; then
        echo "==> $name.png は既にある（飛ばす）"
        return
    fi
    echo
    echo "==> $name"
    echo "    $setup"
    printf "    用意ができたら Enter → そのあと Nullnote の窓をクリック: "
    read -r _
    screencapture -o -w "$SRC/$name.png"
    echo "    撮れた: $SRC/$name.png"
}

echo "App Store 用の元画像を撮ります。"
echo "**窓は大きめに広げておくこと。** 小さいと余白ばかりの絵になります。"
echo "見本の原稿は $SRC/ にあります（01〜03）。"

shoot "01-editor-light" \
      "ライトテーマ。01_Nullnote とは.md を開き、目次・編集・プレビューの3ペインを出す"

shoot "02-preview-dark" \
      "ダークテーマ。02_書式の見本.md を開き、表とコードブロックが両方見える位置まで送る"

shoot "03-multiselect-light" \
      "ライトテーマ。03_一括で書き換える.md の parser を ⌘D で4か所選んだ状態"

shoot "04-toc-dark" \
      "ダークテーマ。長めの原稿を開き、目次が育っているところ（自分の実際の原稿でよい）"

echo
echo "==> 仕上げ"
echo "    ./make-appstore-shots.py $SRC/*.png"
