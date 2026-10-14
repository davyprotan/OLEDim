#!/bin/bash
# Builds a release OLEDim.app into ./dist
# Usage: ./scripts/build-app.sh [--install]
#   --install  also replace /Applications/OLEDim.app and relaunch it
set -euo pipefail
cd "$(dirname "$0")/.."

INSTALL=false
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=true ;;
    *) echo "Unknown option: $arg (usage: $0 [--install])" >&2; exit 1 ;;
  esac
done

VERSION="${VERSION:-0.1.1}"
swift build -c release --arch arm64

APP="dist/OLEDim.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --arch arm64 --show-bin-path)/OLEDim" "$APP/Contents/MacOS/OLEDim"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>OLEDim</string>
  <key>CFBundleDisplayName</key><string>OLEDim</string>
  <key>CFBundleIdentifier</key><string>io.github.oledim</string>
  <key>CFBundleExecutable</key><string>OLEDim</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if $INSTALL; then
  DEST="/Applications/OLEDim.app"
  # Quit the running copy so its binary can be replaced; settings live in UserDefaults and are kept.
  pkill -f "$DEST/Contents/MacOS/OLEDim" && sleep 1 || true
  rm -rf "$DEST"
  cp -R "$APP" "$DEST"
  open "$DEST"
  echo "Installed and launched $DEST"
fi
