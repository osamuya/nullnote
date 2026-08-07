#!/bin/sh
#
# 開発中の確認用。ビルドして、起動中のものを終了させてから、開き直す。
#
#   ./run.sh                 新規書類で起動
#   ./run.sh ~/Desktop/a.md  ファイルを開いて起動
#
# 「直したはずなのに変わらない」を防ぐため、最後にビルド時刻と
# プロセスの開始時刻を並べて表示する。開始時刻が後なら新しいコードが動いている。
#
set -eu

cd "$(dirname "$0")"

echo "==> Debug ビルド"
xcodebuild -scheme Nullnote -configuration Debug build

BUILD_DIR=$(xcodebuild -scheme Nullnote -configuration Debug -showBuildSettings 2>/dev/null \
            | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}' | head -1)
APP="$BUILD_DIR/Nullnote.app"

# 起動しっぱなしだと古いコードを見ることになる。必ず落とす。
if pgrep -f "Nullnote.app/Contents/MacOS/Nullnote" > /dev/null; then
    echo "==> 起動中の Nullnote を終了"
    osascript -e 'tell application "Nullnote" to quit' 2>/dev/null || true
    # 終了しきるまで待つ。ここを待たないと古いプロセスを掴む。
    i=0
    while pgrep -f "Nullnote.app/Contents/MacOS/Nullnote" > /dev/null; do
        i=$((i + 1))
        [ "$i" -gt 20 ] && { echo "    終了しないので強制終了"; pkill -f "Nullnote.app/Contents/MacOS/Nullnote"; break; }
        sleep 0.5
    done
fi

echo "==> 起動"
if [ $# -gt 0 ]; then
    open -a "$APP" "$@"
else
    open -a "$APP"
fi

sleep 4

echo "==> 確認"
PID=$(pgrep -f "Nullnote.app/Contents/MacOS/Nullnote" | head -1 || true)
if [ -z "$PID" ]; then
    echo "    起動していません" >&2
    exit 1
fi
RUNNING=$(ps -o comm= -p "$PID")
EXPECTED="$APP/Contents/MacOS/Nullnote"

# 実際にコードが入っているのは Debug ビルドでは .debug.dylib の方。
CODE="$APP/Contents/MacOS/Nullnote.debug.dylib"
[ -f "$CODE" ] || CODE="$EXPECTED"

echo "    起動中:       $RUNNING"
echo "    コードの更新: $(stat -f '%Sm' -t '%m/%d %T' "$CODE")"
echo "    プロセス開始: $(ps -o lstart= -p "$PID" | sed 's/^ *//')"
echo
if [ "$RUNNING" = "$EXPECTED" ]; then
    echo "    ✅ いまビルドしたものが動いています"
else
    echo "    ❌ 別の場所のアプリが動いています" >&2
    echo "       期待: $EXPECTED" >&2
    exit 1
fi
