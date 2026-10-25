#!/bin/bash
# 打包並安裝到 /Applications（覆蓋舊版）。用法：scripts/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh
pkill -x MyBrowser 2>/dev/null || true
rm -rf "/Applications/My Browser.app"
cp -R "build/My Browser.app" "/Applications/My Browser.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/My Browser.app"
echo "已安裝到 /Applications/My Browser.app"
