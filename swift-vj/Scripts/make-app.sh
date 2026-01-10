#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="RealityKitVJKitchenSink"
BUILD_DIR="$ROOT_DIR/Build"
APP_DIR="$BUILD_DIR/${APP_NAME}.app"
EXECUTABLE_PATH="$ROOT_DIR/.build/release/${APP_NAME}"
RESOURCE_BUNDLE="$ROOT_DIR/.build/release/${APP_NAME}.resources"

cd "$ROOT_DIR"

swift build -c release --product "$APP_NAME"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE"/* "$APP_DIR/Contents/Resources/"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.swiftvj.${APP_NAME}</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
</dict>
</plist>
PLIST

echo "App bundle created at $APP_DIR"
