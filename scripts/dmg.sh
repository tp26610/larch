#!/bin/bash
# 把 build/Larch.app 包成 dmg（含 /Applications 捷徑）。用法：scripts/dmg.sh [版本號，預設讀根目錄 VERSION]
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(tr -d "[:space:]" < VERSION)}"
scripts/bundle.sh "$VERSION"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R build/Larch.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="build/Larch-$VERSION-arm64.dmg"
rm -f "$DMG"
hdiutil create -volname "Larch" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "完成：$DMG"
