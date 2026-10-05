#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
if ! xcodebuild -version >/dev/null 2>&1; then
  echo "Full Xcode is required for the SwiftData compiler plugin. Install Xcode, select it in Xcode Settings > Locations > Command Line Tools, then rerun this script." >&2
  exit 1
fi
cd "$ROOT_DIR"
# --show-bin-path only prints a path. Build first so an old executable can never
# be bundled after source changes or a failed compilation.
swift build --disable-sandbox --product LifeReplayMac
BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
APP_DIR="$ROOT_DIR/.build/LifeReplayMac.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
cp "$BIN_DIR/LifeReplayMac" "$MACOS_DIR/LifeReplayMac"
chmod +x "$MACOS_DIR/LifeReplayMac"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>LifeReplayMac</string>
  <key>CFBundleIdentifier</key>
  <string>com.mohitgrover.LifeReplayMac</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Life Replay</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Life Replay reads the active browser tab domain to build your local activity timeline.</string>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
</dict>
</plist>
PLIST

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"
xattr -cr "$APP_DIR"
codesign --force --deep --sign - --identifier com.mohitgrover.LifeReplayMac "$APP_DIR" >/dev/null

echo "$APP_DIR"
