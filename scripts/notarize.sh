#!/bin/bash
# 公證並釘上票證。需先用 SIGN_IDENTITY 簽好 dmg（scripts/dmg.sh）。
# 一次性設定憑證（App 專用密碼從 appleid.apple.com 產生）：
#   xcrun notarytool store-credentials larch-notary --apple-id <Apple ID> --team-id <TEAMID>
# 用法：SIGN_IDENTITY="Developer ID Application: ..." scripts/dmg.sh && scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="$(tr -d "[:space:]" < VERSION)"
DMG="build/Larch-$VERSION-arm64.dmg"
[ -f "$DMG" ] || { echo "找不到 $DMG，先跑 scripts/dmg.sh" >&2; exit 1; }
xcrun notarytool submit "$DMG" --keychain-profile "${NOTARY_PROFILE:-larch-notary}" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature -v "$DMG"
echo "完成：$DMG 已公證"
