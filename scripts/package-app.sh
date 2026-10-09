#!/usr/bin/env bash
# Builds the app and wraps it as build/ArcTV.app and build/ArcTV-<version>.dmg.
#
#   scripts/package-app.sh 0.1.0          (needs macOS with the Swift toolchain)
#   API_BASE_URL=https://api.example.com scripts/package-app.sh 0.1.0
#
# The app is NOT signed with an Apple Developer ID: it gets an "ad-hoc" signature (free; Apple Silicon Macs refuse to run a program with no
# signature at all) and is not notarized, so macOS shows a warning the first time it is opened (see README.md).
set -euo pipefail

VERSION="${1:-0.0.0-dev}"
API_BASE_URL="${API_BASE_URL:-}"
cd "$(dirname "$0")/.."

echo "Building ArcTV $VERSION (universal: arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

APP="build/ArcTV.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ArcTV" "$APP/Contents/MacOS/ArcTV"

# CFBundleVersion must be a plain number-ish string; the marketing version can be anything.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ArcTV</string>
  <key>CFBundleIdentifier</key><string>tv.arc.mac</string>
  <key>CFBundleName</key><string>Arc TV</string>
  <key>CFBundleDisplayName</key><string>Arc TV</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>ArcTVAPIBaseURL</key><string>${API_BASE_URL}</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

echo "Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --verbose=2 "$APP"

echo "Making the DMG"
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Arc TV" -srcfolder "$STAGE" -ov -format UDZO "build/ArcTV-${VERSION}.dmg"
rm -rf "$STAGE"
echo "Done: build/ArcTV-${VERSION}.dmg"
