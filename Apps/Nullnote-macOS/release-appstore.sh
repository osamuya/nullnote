#!/bin/sh
#
# App Store に出す。アーカイブ → 書き出し → 中身の確認 → アップロード。
#
#   ./release-appstore.sh          # .pkg を作って確かめるところまで（既定）
#   ./release-appstore.sh upload   # 確かめたうえで App Store Connect に上げる
#
# 出来上がり: build/appstore/Nullnote.pkg
#
# ## release-dmg.sh との違い
#
# **別物として扱う。** DMG 配布は Developer ID 証明書＋公証、App Store は
# Apple Distribution 証明書＋App Store Connect の審査。証明書もプロファイルも
# 書き出し方法も違うので、片方の成功はもう片方の保証にならない。
#
# ## 事前に一度だけ必要なもの
#
# 1. Developer Portal で Bundle ID `com.sabanote.Nullnote` を登録しておく
#    （capability は何も選ばない。App Sandbox は一覧に無い）
# 2. App Store Connect で同じ Bundle ID のアプリレコードを作っておく
#    （**これが無いとアップロードは弾かれる**）
# 3. Xcode → Settings → Accounts に Apple ID がサインイン済みであること
#
# ## アップロードの認証（任意）
#
# 既定では Xcode にサインイン済みのアカウントを使う。
# CI などで非対話にしたいときは App Store Connect API キーを環境変数で渡す。
#
#   ASC_KEY_PATH=~/private_keys/AuthKey_XXXX.p8 \
#   ASC_KEY_ID=XXXXXXXXXX \
#   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
#   ./release-appstore.sh upload
#
# ## 押さえておくこと
#
# - **ビルド番号は同じ値を二度使えない。** 却下されたビルドの番号も再利用できない。
#   出すたびに CURRENT_PROJECT_VERSION を増やす。バージョン（1.0）は据え置きでよい。
# - **`get-task-allow` が残っていると審査で弾かれる。** 書き出しで外れるが、
#   pkg を開いて実際に確かめる。
# - **公証は要らない。** App Store 側で行われる。ここで notarytool を呼ぶと二度手間になる。
set -eu

cd "$(dirname "$0")"

# **変数の直後に全角文字を置くときは `${VAR}` と括る。** `/bin/sh` は全角文字を
# 変数名の一部と見なすので、`$VERSION（` は `VERSION（` という名前になる。
# `set -u` と合わさって unbound variable で止まる（実測。初回実行で踏んだ）。

MODE="${1:-export}"
BUILD=build
ARCHIVE="$BUILD/Nullnote-appstore.xcarchive"
EXPORT="$BUILD/appstore"
OPTS=ExportOptions-appstore.plist

[ -f "$OPTS" ] || { echo "$OPTS がありません" >&2; exit 1; }

echo "==> 事前確認"
security find-identity -v -p codesigning | grep -q "Apple Distribution" || {
    echo "    Apple Distribution 証明書がありません（アプリ本体の署名に要る）。" >&2
    echo "    Xcode → Settings → Apple Accounts → アカウントの行 → チームの行" >&2
    echo "    → Manage Certificates… → 左下の「+ ⌄」→ Apple Distribution" >&2
    exit 1
}

# **.pkg の署名は別の証明書。** アプリ本体（Apple Distribution）だけでは書き出せない。
# インストーラ証明書は codesigning ポリシーに出てこないので、`-p` を付けずに見る。
security find-identity -v | grep -q "3rd Party Mac Developer Installer" || {
    echo "    Mac Installer Distribution 証明書がありません（.pkg の署名に要る）。" >&2
    echo "    同じ「+ ⌄」から Mac Installer Distribution を作る" >&2
    echo "    （一覧には 3rd Party Mac Developer Installer と出る）" >&2
    exit 1
}

# サンドボックスとブックマークの権限は、消えると静かに壊れる。毎回見る。
for KEY in com.apple.security.app-sandbox com.apple.security.files.bookmarks.app-scope; do
    grep -q "$KEY" Supporting/Nullnote.entitlements || {
        echo "    entitlements に $KEY がありません" >&2
        exit 1
    }
done

echo "==> アーカイブ"
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild -scheme Nullnote -configuration Release \
           -archivePath "$ARCHIVE" -allowProvisioningUpdates archive > "$BUILD/archive-appstore.log" 2>&1 || {
    echo "    失敗。$BUILD/archive-appstore.log を見てください" >&2
    exit 1
}

APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/Nullnote.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_IN_ARCHIVE/Contents/Info.plist")
BUILDNO=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_IN_ARCHIVE/Contents/Info.plist")
echo "    バージョン ${VERSION}（ビルド ${BUILDNO}）"

echo "==> App Store 用に書き出し"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
           -exportOptionsPlist "$OPTS" \
           -exportPath "$EXPORT" -allowProvisioningUpdates > "$BUILD/export-appstore.log" 2>&1 || {
    echo "    失敗。$BUILD/export-appstore.log を見てください" >&2
    exit 1
}

PKG=$(ls "$EXPORT"/*.pkg 2>/dev/null | head -1)
[ -n "$PKG" ] || { echo "    .pkg ができていません。$BUILD/export-appstore.log を見てください" >&2; exit 1; }

echo "==> 中身を確かめる"
# pkg を開いて、実際に入るアプリの署名と権限を見る。plist を見るだけでは足りない。
TMP="$BUILD/pkg-check"
rm -rf "$TMP"
pkgutil --expand-full "$PKG" "$TMP" > /dev/null
APP=$(find "$TMP" -maxdepth 4 -name "Nullnote.app" -type d | head -1)
[ -n "$APP" ] || { echo "    pkg の中に Nullnote.app が見つかりません" >&2; exit 1; }

ENT=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null || codesign -d --entitlements - "$APP" 2>&1)

case "$ENT" in
    *get-task-allow*) echo "    ❌ get-task-allow が残っています。このままでは弾かれます" >&2; exit 1 ;;
esac
case "$ENT" in
    *app-sandbox*) ;;
    *) echo "    ❌ サンドボックスが有効になっていません" >&2; exit 1 ;;
esac
case "$ENT" in
    *bookmarks.app-scope*) ;;
    *) echo "    ❌ bookmarks.app-scope がありません。フォルダの許可が毎回聞き直しになります" >&2; exit 1 ;;
esac

codesign -dvv "$APP" 2>&1 | grep -E "Authority|TeamIdentifier" | sed 's/^/    /'
echo "    ✅ 署名と権限は問題なし"

if [ "$MODE" != "upload" ]; then
    echo
    echo "    ✅ $PKG"
    echo "       $(du -h "$PKG" | cut -f1)"
    echo
    echo "    上げるときは: ./release-appstore.sh upload"
    exit 0
fi

echo "==> App Store Connect にアップロード"
AUTH=""
if [ -n "${ASC_KEY_PATH:-}" ]; then
    AUTH="-authenticationKeyPath ${ASC_KEY_PATH} -authenticationKeyID ${ASC_KEY_ID} -authenticationKeyIssuerID ${ASC_ISSUER_ID}"
fi

# 同じアーカイブを destination=upload で書き出し直す。
# 手元の .pkg を上げるのではなく、Xcode に送らせるのが今の作法。
sed 's|<string>export</string>|<string>upload</string>|' "$OPTS" > "$BUILD/ExportOptions-upload.plist"

# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
           -exportOptionsPlist "$BUILD/ExportOptions-upload.plist" \
           -exportPath "$BUILD/upload" -allowProvisioningUpdates $AUTH

echo
echo "    ✅ ${VERSION}（ビルド ${BUILDNO}）を送りました"
echo "       App Store Connect の TestFlight タブに出るまで 5〜30 分ほどかかります"
echo "       処理が終わるとメールが来ます。**Missing Compliance が付いたら** Info.plist の"
echo "       ITSAppUsesNonExemptEncryption を確認してください"
