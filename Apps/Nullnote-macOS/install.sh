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

# 起動中だと差し替えられないので、先に終了させる。
if pgrep -f "Nullnote.app/Contents/MacOS/Nullnote" > /dev/null; then
    echo "==> 起動中の Nullnote を終了"
    osascript -e 'tell application "Nullnote" to quit' || true
    sleep 2
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
echo "    ターミナルからは:  open -a $DESTINATION ファイル.md"
