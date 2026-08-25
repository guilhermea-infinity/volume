#!/bin/bash
# Builds Volume.app into build/ — run again any time the source changes.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

if [ ! -f assets/AppIcon.icns ]; then
  TMP_ICONSET="$(mktemp -d)/Volume.iconset"
  swift scripts/make-icon.swift "$TMP_ICONSET"
  iconutil -c icns "$TMP_ICONSET" -o assets/AppIcon.icns
fi

APP=build/Volume.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Volume "$APP/Contents/MacOS/Volume"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Volume</string>
    <key>CFBundleDisplayName</key>     <string>Volume</string>
    <key>CFBundleIdentifier</key>      <string>com.guilherme.volume</string>
    <key>CFBundleExecutable</key>      <string>Volume</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Volume reads your calendar to log meeting time automatically.</string>
    <key>NSCalendarsUsageDescription</key>
    <string>Volume reads your calendar to log meeting time automatically.</string>
</dict>
</plist>
PLIST

codesign --force -s - "$APP"
echo "Built $APP"
