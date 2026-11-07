#!/bin/bash
# 打包並安裝到 /Applications（覆蓋舊版）。用法：scripts/install.sh
# 簽章：未設 SIGN_IDENTITY 時，自動使用鑰匙圈裡 Team D39W45PJ9Y 的 Developer ID Application；找不到才退回 ad-hoc。
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM_ID="D39W45PJ9Y"
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n "s/.*\"\(Developer ID Application: .*($TEAM_ID)\)\".*/\1/p" | head -1)"
fi
if [ -n "$SIGN_IDENTITY" ]; then
  echo "簽章身分：$SIGN_IDENTITY"
  export SIGN_IDENTITY
else
  echo "找不到 Developer ID 憑證，退回 ad-hoc 簽章" >&2
fi
scripts/bundle.sh
pkill -x Larch 2>/dev/null || true
rm -rf "/Applications/Larch.app"
cp -R "build/Larch.app" "/Applications/Larch.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Larch.app"
echo "已安裝到 /Applications/Larch.app"
