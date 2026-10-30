#!/bin/bash
# 把 release 版包成 build/Larch.app（ad-hoc 簽章）。版本號讀根目錄 VERSION。用法：scripts/bundle.sh
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
VERSION="$(tr -d "[:space:]" < VERSION)"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/Larch.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp "$(swift build -c release --show-bin-path)/Larch" "$APP/Contents/MacOS/Larch"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Larch</string>
  <key>CFBundleDisplayName</key><string>Larch</string>
  <key>CFBundleIdentifier</key><string>com.brianyeh.larch</string>
  <key>CFBundleExecutable</key><string>Larch</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Web URL</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>CFBundleURLSchemes</key><array><string>http</string><string>https</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>HTML document</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSItemContentTypes</key><array><string>public.html</string></array>
    <key>CFBundleTypeExtensions</key><array><string>html</string><string>htm</string></array>
  </dict></array>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --sign - "$APP"
echo "完成：$APP"
