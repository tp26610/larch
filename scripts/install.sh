#!/bin/bash
# 打包並安裝到 /Applications（覆蓋舊版）。用法：scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh
pkill -x Larch 2>/dev/null || true
rm -rf "/Applications/Larch.app"
cp -R "build/Larch.app" "/Applications/Larch.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Larch.app"
echo "已安裝到 /Applications/Larch.app"
