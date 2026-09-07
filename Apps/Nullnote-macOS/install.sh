#!/bin/sh
#
# Nullnote を /Applications にインストールする。
#
# 開発中のアプリは DerivedData の中にあり、Clean Build Folder で消える。
# 常用するには Release ビルドを /Applications に置く。
# コードを直したあとは、このスクリプトを実行し直せば入れ替わる。
#
#   ./install.sh
#
set -eu

cd "$(dirname "$0")"

DESTINATION=/Applications/Nullnote.app

echo "==> Release ビルド"
xcodebuild -scheme Nullnote -configuration Release build

BUILD_DIR=$(xcodebuild -scheme Nullnote -configuration Release -showBuildSettings 2>/dev/null \
            | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)
SOURCE="$BUILD_DIR/Nullnote.app"

if [ ! -d "$SOURCE" ]; then
    echo "ビルド結果が見つかりません: $SOURCE" >&2
    exit 1
fi

# 起動中だと差し替えても、**古いプロセスが動き続ける**。
# 差し替えは中身の入れ替えでしかなく、動いているアプリは入れ替わらない。
# ここを確かめないと「入れ替えたのに直っていない」になる
# （実測: 20:17 に入れ替えたのに、19:49 に始まったプロセスが動いたままだった）。
RUNNING="/Applications/Nullnote.app/Contents/MacOS/Nullnote"
if pgrep -f "$RUNNING" > /dev/null; then
    echo "==> 起動中の Nullnote を終了"
    # **Bundle ID で狙う。** 名前で送ると、開発版（DerivedData の Nullnote.app）に届く。
    osascript -e 'tell application id "com.sabanote.Nullnote" to quit' || true

    # 終了しきるまで待つ。書類を扱う道具なので、**強制終了はしない**
    # （保存していない書き掛けが消える）。終わらなければ手で閉じてもらう。
    i=0
    while pgrep -f "$RUNNING" > /dev/null; do
        i=$((i + 1))
        if [ "$i" -gt 20 ]; then
            echo "    終了できません。保存していない書類が残っているかもしれません。" >&2
            echo "    Nullnote を手で終了してから、もう一度実行してください。" >&2
            exit 1
        fi
        sleep 0.5
    done
fi

echo "==> $DESTINATION へコピー"
rm -rf "$DESTINATION"
cp -R "$SOURCE" "$DESTINATION"

# Finder と Dock にアイコンの変更を知らせる。
touch "$DESTINATION"

echo "==> 完了"
/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DESTINATION/Contents/Info.plist" \
    | xargs -I{} echo "    バージョン {}"
echo
echo "    Finder / Launchpad / Dock から起動できます。"
echo "    ※ 開き直すまで、直した内容は反映されません。"
echo "    ターミナルからは:  open -a $DESTINATION ファイル.md"
