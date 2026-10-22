#!/bin/bash
# Builds build/MicKeeper.app from the MicKeeperApp target and ad-hoc signs it.
#
#   ./scripts/build-app.sh            build only
#   ./scripts/build-app.sh --install  also copy to ~/Applications/MicKeeper.app (no admin needed)
#
# "Iniciar com o sistema" registers the app at its current path, so use the installed copy for it:
# build/ is wiped on every build.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="0.2.0"
APP="build/MicKeeper.app"

swift build -c release --product MicKeeperApp
BIN_DIR="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MicKeeperApp" "$APP/Contents/MacOS/MicKeeper"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Translations (pt-BR, en, es) live in the core library's resource bundle.
cp -R "$BIN_DIR/MicKeeper_MicKeeperCore.bundle" "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>MicKeeper</string>
    <key>CFBundleIdentifier</key>
    <string>com.alencar.mickeeper</string>
    <key>CFBundleName</key>
    <string>MicKeeper</string>
    <key>CFBundleDisplayName</key>
    <string>MicKeeper</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>pt-BR</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>pt-BR</string>
        <string>en</string>
        <string>es</string>
    </array>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/MicKeeper.app"
    if pgrep -xq MicKeeper; then
        echo "Quitting the running MicKeeper"
        pkill -x MicKeeper || true
        sleep 1
    fi
    mkdir -p "$HOME/Applications"
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    # Make Finder and the Dock notice the new icon.
    touch "$DEST"
    echo "Installed $DEST"
fi
