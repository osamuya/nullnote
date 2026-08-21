#!/bin/sh
#
# 配布用の DMG を作る。署名 → 公証 → ステープルまで通して、最後に判定を確かめる。
#
#   ./release-dmg.sh
#
# 出来上がり: build/Nullnote-<バージョン>.dmg
#
# ## 事前に一度だけ必要なもの
#
# 1. Developer ID Application 証明書
#    Xcode → Settings → Apple Accounts → 緑チェックのあるチーム
#    → Manage Certificates… → 左下の「+ ⌄」→ Developer ID Application
#
# 2. 公証用の認証情報（アプリ用パスワードをキーチェーンに保存）
#    xcrun notarytool store-credentials nullnote-notary \
#      --apple-id <あなたの Apple ID> --team-id 542DBL2NGA
#
# ## 押さえておくこと
#
# - **DMG 自体にも署名と公証が要る。** 中のアプリだけ済ませても、
#   DMG が未署名だと Gatekeeper は `rejected（no usable signature）` を返す。実測で確かめた。
# - **署名し直すとステープルは無効になる。** DMG は作り直す → 署名 → 公証 → ステープルの順に固定。
# - 初回の署名時、キーチェーンへのアクセス許可を聞かれる。
#   **Mac のログインパスワード**を入れて「常に許可」を選ぶと以後は聞かれない。
set -eu

cd "$(dirname "$0")"

TEAM_ID=542DBL2NGA
SIGNING_IDENTITY="Developer ID Application: Osamu Yamakami ($TEAM_ID)"
NOTARY_PROFILE=nullnote-notary
BUILD=build
ARCHIVE="$BUILD/Nullnote.xcarchive"
EXPORT="$BUILD/export"
STAGING="$BUILD/dmg"

# 材料が揃っているか先に見る。途中で気づくと数分無駄になる。
echo "==> 事前確認"
security find-identity -v -p codesigning | grep -q "$SIGNING_IDENTITY" || {
    echo "    Developer ID Application 証明書がありません。ファイル冒頭の手順1を参照" >&2
    exit 1
}
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1 || {
    echo "    公証の認証情報がありません。ファイル冒頭の手順2を参照" >&2
    exit 1
}

echo "==> アーカイブ"
rm -rf "$ARCHIVE" "$EXPORT" "$STAGING"
xcodebuild -scheme Nullnote -configuration Release \
           -archivePath "$ARCHIVE" -allowProvisioningUpdates archive > "$BUILD/archive.log" 2>&1 || {
    echo "    失敗。$BUILD/archive.log を見てください" >&2
    exit 1
}

echo "==> Developer ID で書き出し"
cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
	<key>signingStyle</key>
	<string>automatic</string>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
           -exportOptionsPlist "$BUILD/ExportOptions.plist" \
           -exportPath "$EXPORT" -allowProvisioningUpdates > "$BUILD/export.log" 2>&1 || {
    echo "    失敗。$BUILD/export.log を見てください" >&2
    exit 1
}

APP="$EXPORT/Nullnote.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="$BUILD/Nullnote-$VERSION.dmg"
echo "    バージョン $VERSION"

# 配布ビルドには残っていてはいけない。書き出しで外れるが、確かめる。
if codesign -d --entitlements - "$APP" 2>&1 | grep -q "get-task-allow"; then
    echo "    com.apple.security.get-task-allow が残っています。配布できません" >&2
    exit 1
fi

echo "==> アプリを公証"
ditto -c -k --keepParent "$APP" "$BUILD/Nullnote.zip"
xcrun notarytool submit "$BUILD/Nullnote.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"

echo "==> DMG を作る"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
# cp ではなく ditto。拡張属性（公証の証明を含む）をそのまま運ぶ。
ditto "$APP" "$STAGING/Nullnote.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Nullnote $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" > /dev/null

echo "==> DMG に署名して公証"
codesign --sign "$SIGNING_IDENTITY" --timestamp "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> 判定"
spctl -a -t open --context context:primary-signature -v "$DMG"
spctl -a -t exec -v "$STAGING/Nullnote.app"

# 落としたファイルが壊れていないかを、利用者が確かめられるようにする。
# 配布ページに併記する。ファイルと一緒に置くのではなく、**ページ側に書く**こと。
# 同じ場所に置くと、両方すり替えられたときに意味を成さない。
SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
echo "$SHA" > "$DMG.sha256"

echo
echo "    ✅ $DMG"
echo "       $(du -h "$DMG" | cut -f1)"
echo "       SHA-256: $SHA"
echo
echo "    サーバーへ置く:"
echo "      rsync -av -e \"ssh -p 2222\" $DMG \\"
echo "        <配布先>"
