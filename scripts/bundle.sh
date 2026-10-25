#!/bin/bash
# 把 release 版包成 build/My Browser.app（ad-hoc 簽章）。用法：scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/My Browser.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/MyBrowser" "$APP/Contents/MacOS/MyBrowser"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>My Browser</string>
  <key>CFBundleDisplayName</key><string>My Browser</string>
  <key>CFBundleIdentifier</key><string>com.brianyeh.my-browser-mac</string>
  <key>CFBundleExecutable</key><string>MyBrowser</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "完成：$APP"
