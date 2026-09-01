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

# **Debug 版だけを狙う。** Bundle ID を分けてあるので（`com.sabanote.Nullnote.debug`）、
# 実行ファイルのパスで照合すれば /Applications 版を巻き込まない。
# ここを "Nullnote.app/Contents/MacOS/Nullnote" にすると、普段使いの方まで落とす。
PATTERN="$BUILD_DIR/Nullnote.app/Contents/MacOS/Nullnote"

# 起動しっぱなしだと古いコードを見ることになる。必ず落とす。
if pgrep -f "$PATTERN" > /dev/null; then
    echo "==> 起動中の Nullnote を終了"
    # 名前で quit を送る。同名のアプリが複数あるとき（DerivedData のものと
    # /Applications のもの）片方にしか届かないので、残りは下で強制終了する。
    # 名前で quit を送っても、同名のアプリが2つあると片方にしか届かない。
    # Debug 版は用が済んだら落としてよいので、パスを狙って直接止める。
    pkill -f "$PATTERN" 2>/dev/null || true
    # 終了しきるまで待つ。ここを待たないと古いプロセスを掴む。
    i=0
    while pgrep -f "$PATTERN" > /dev/null; do
        i=$((i + 1))
        [ "$i" -gt 20 ] && { echo "    終了しないので強制終了"; pkill -f "$PATTERN"; break; }
        sleep 0.5
    done

    # 強制終了したあとも、プロセスが消えるまで待つ。
    # ここを飛ばすと LaunchServices がまだ「起動中」と思っていて、
    # 続く open が -600（procNotFound）で失敗する。
    i=0
    while pgrep -f "$PATTERN" > /dev/null; do
        i=$((i + 1))
        [ "$i" -gt 20 ] && { echo "    プロセスが残っています" >&2; exit 1; }
        sleep 0.5
    done
fi

echo "==> 起動"
# プロセスが消えても LaunchServices の側が追いつくまで一拍ある。
# 一度の失敗で諦めず、少しだけ待って開き直す。
i=0
until open -a "$APP" "$@" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 10 ]; then
        echo "    起動できません。理由を出します" >&2
        open -a "$APP" "$@"      # ← エラーを隠さずに出して終わる
        exit 1
    fi
    sleep 0.5
done

sleep 4

echo "==> 確認"
# **Debug 版だけを探す。** ここを "Nullnote.app/Contents/MacOS/Nullnote" にすると、
# 普段使いの /Applications 版を先に拾って「別のアプリが動いている」と誤判定する
# （実測。Bundle ID を分けたあとは両方が並んで動くのが正常）。
EXPECTED="$APP/Contents/MacOS/Nullnote"
PID=$(pgrep -f "$PATTERN" | head -1 || true)
if [ -z "$PID" ]; then
    echo "    起動していません" >&2
    exit 1
fi
RUNNING=$(ps -o comm= -p "$PID")

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
