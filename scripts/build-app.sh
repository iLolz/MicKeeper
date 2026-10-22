#!/bin/bash
# Builds build/MicPriority.app from the MicPriorityApp target and ad-hoc signs it.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="0.2.0"
APP="build/MicPriority.app"

swift build -c release --product MicPriorityApp
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MicPriorityApp" "$APP/Contents/MacOS/MicPriority"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MicPriority</string>
    <key>CFBundleIdentifier</key>
    <string>com.alencar.micpriority</string>
    <key>CFBundleName</key>
    <string>MicPriority</string>
    <key>CFBundleDisplayName</key>
    <string>MicPriority</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt-BR</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"
