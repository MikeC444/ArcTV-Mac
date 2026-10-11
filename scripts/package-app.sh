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

echo "Building ArcTV $VERSION (Apple Silicon; the torrent engine is built for it only)"
# The final link sometimes fails on libsmbclient symbols (the cause is not known); the same build works the next time, so it is tried again.
built=no
for attempt in 1 2 3 4 5; do
  if swift build -c release --arch arm64; then built=yes; break; fi
  echo "Build failed (attempt $attempt of 5); trying again from a clean build with freshly downloaded libraries"
  rm -rf .build "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/Library/org.swift.swiftpm"
done
[ "$built" = yes ] || exit 1
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/ArcTV.app"
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ArcTV" "$APP/Contents/MacOS/ArcTV"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# The torrent engine (libtorrent) and the libraries it needs (OpenSSL, whichever version Homebrew has) come from Homebrew: copy them inside the
# app and point everything at the copies, so the app runs on a Mac that has no Homebrew. Dependencies are found by reading each library's own
# list, so a new OpenSSL version in Homebrew needs no change here.
FW="$APP/Contents/Frameworks"
mkdir -p "$FW"
BREW_PREFIX="$(brew --prefix)"
copy_deps() {
  local file="$1" dep real name
  otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      "$BREW_PREFIX"/*|/opt/homebrew/*|/usr/local/opt/*|/usr/local/Cellar/*)
        name="$(basename "$dep")"
        if [ ! -f "$FW/$name" ]; then
          real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$dep")"
          cp "$real" "$FW/$name"
          chmod u+w "$FW/$name"
          install_name_tool -id "@rpath/$name" "$FW/$name"
          copy_deps "$FW/$name"
        fi ;;
    esac
  done
}
fix_refs() {
  local file="$1" dep
  otool -L "$file" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      "$BREW_PREFIX"/*|/opt/homebrew/*|/usr/local/opt/*|/usr/local/Cellar/*)
        install_name_tool -change "$dep" "@rpath/$(basename "$dep")" "$file" ;;
    esac
  done
}
copy_deps "$APP/Contents/MacOS/ArcTV"
fix_refs "$APP/Contents/MacOS/ArcTV"
for lib in "$FW"/*.dylib; do fix_refs "$lib"; done
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ArcTV" 2>/dev/null || true
echo "Frameworks inside the app:"; ls "$FW"
if otool -L "$APP/Contents/MacOS/ArcTV" "$FW"/*.dylib | grep -qE "/opt/homebrew|/usr/local/(opt|Cellar)"; then
  echo "A Homebrew path is still referenced:"; otool -L "$APP/Contents/MacOS/ArcTV" "$FW"/*.dylib | grep -E "/opt/homebrew|/usr/local/(opt|Cellar)"; exit 1
fi

# CFBundleVersion must be a plain number-ish string; the marketing version can be anything.
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>ArcTV</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleIdentifier</key><string>tv.arc.mac</string>
  <key>CFBundleName</key><string>Arc TV</string>
  <key>CFBundleDisplayName</key><string>Arc TV</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
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
# The app holds the mpv player's libraries, so it is large. On a build machine (CI), free the build caches first so the disk image has room.
if [ -n "${CI:-}" ]; then
  rm -rf .build "$HOME/Library/Caches/org.swift.swiftpm" "$HOME/Library/org.swift.swiftpm" 2>/dev/null || true
fi
DMG="build/ArcTV-${VERSION}.dmg"

# The styled disk image: a dark window with the app on the left, Applications on the right and an arrow between them (dmgbuild writes the
# window's look without scripting Finder). If anything in it fails, the plain image below is made instead, so a release is never held up by it.
STYLED=no
if python3 -m venv build/dmgenv >/dev/null 2>&1 && build/dmgenv/bin/pip install --quiet dmgbuild >/dev/null 2>&1; then
  if tiffutil -cathidpicheck Resources/dmg-background.png Resources/dmg-background@2x.png -out build/dmg-background.tiff \
     && build/dmgenv/bin/dmgbuild -s scripts/dmg-settings.py -D app="$APP" -D background=build/dmg-background.tiff -D icon=Resources/AppIcon.icns "Arc TV" "$DMG"; then
    STYLED=yes
  fi
fi

if [ "$STYLED" != yes ]; then
  echo "The styled disk image could not be made; making a plain one"
  rm -f "$DMG"
  STAGE="build/dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  APP_KB=$(du -sk "$STAGE" | cut -f1)
  SIZE_MB=$(( APP_KB / 1024 * 4 / 3 + 64 ))
  echo "App is $((APP_KB / 1024)) MB; making a ${SIZE_MB} MB image"
  hdiutil create -volname "Arc TV" -srcfolder "$STAGE" -size "${SIZE_MB}m" -ov -format UDZO "$DMG"
  rm -rf "$STAGE"
fi
rm -rf build/dmgenv build/dmg-background.tiff
echo "Disk image: $([ "$STYLED" = yes ] && echo styled || echo plain)"
echo "Done: build/ArcTV-${VERSION}.dmg"
