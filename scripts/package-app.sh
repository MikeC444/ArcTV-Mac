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
# The final link sometimes fails on libsmbclient symbols (the cause is not known); the same build works the next time, so it is tried again.
built=no
for attempt in 1 2 3 4 5; do
  if swift build -c release --arch arm64 --arch x86_64; then built=yes; break; fi
  echo "Build failed (attempt $attempt of 5); trying again"
done
[ "$built" = yes ] || exit 1
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

# The app holds the mpv player's libraries, so it is large. On a build machine (CI), free the build caches first so the disk image has room,
# and give the image an explicit size (the app's size plus a third) rather than trusting hdiutil's guess.
if [ -n "${CI:-}" ]; then
  rm -rf .build "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/Library/org.swift.swiftpm" 2>/dev/null || true
fi
APP_KB=$(du -sk "$STAGE" | cut -f1)
SIZE_MB=$(( APP_KB / 1024 * 4 / 3 + 64 ))
echo "App is $((APP_KB / 1024)) MB; making a ${SIZE_MB} MB image"
hdiutil create -volname "Arc TV" -srcfolder "$STAGE" -size "${SIZE_MB}m" -ov -format UDZO "build/ArcTV-${VERSION}.dmg"
rm -rf "$STAGE"
echo "Done: build/ArcTV-${VERSION}.dmg"
