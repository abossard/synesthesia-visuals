#!/bin/bash
# bundle-app.sh - Create a proper macOS .app bundle from SPM executable

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/debug"
APP_NAME="Swift VJ"
BUNDLE_DIR="$SCRIPT_DIR/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🔨 Building SwiftVJApp..."
swift build --target SwiftVJApp

echo "📦 Creating app bundle: $APP_NAME.app"

# Clean and create bundle structure
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executable
cp "$BUILD_DIR/SwiftVJApp" "$MACOS_DIR/SwiftVJApp"

# Ensure bundled frameworks resolve at runtime.
# SPM binaries include @rpath lookups, but default rpaths do not include the app Frameworks folder.
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/SwiftVJApp" 2>/dev/null || true

# Copy resources from bundle
if [ -d "$BUILD_DIR/SwiftVJApp_SwiftVJApp.bundle" ]; then
    cp -R "$BUILD_DIR/SwiftVJApp_SwiftVJApp.bundle/"* "$RESOURCES_DIR/"
fi

# Create Info.plist
cat > "$CONTENTS_DIR/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>SwiftVJApp</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.synesthesia.SwiftVJApp</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Swift VJ</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

# Create icns from PNG icons if iconutil is available
ICONSET_SRC="$SCRIPT_DIR/Sources/SwiftVJApp/Resources/Assets.xcassets/AppIcon.appiconset"
if [ -d "$ICONSET_SRC" ]; then
    echo "🎨 Creating AppIcon.icns..."
    ICONSET_TMP="/tmp/AppIcon.iconset"
    rm -rf "$ICONSET_TMP"
    mkdir -p "$ICONSET_TMP"
    
    # Copy icons with macOS iconset naming
    cp "$ICONSET_SRC/icon_16x16.png" "$ICONSET_TMP/icon_16x16.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_16x16@2x.png" "$ICONSET_TMP/icon_16x16@2x.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_32x32.png" "$ICONSET_TMP/icon_32x32.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_32x32@2x.png" "$ICONSET_TMP/icon_32x32@2x.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_128x128.png" "$ICONSET_TMP/icon_128x128.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_128x128@2x.png" "$ICONSET_TMP/icon_128x128@2x.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_256x256.png" "$ICONSET_TMP/icon_256x256.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_256x256@2x.png" "$ICONSET_TMP/icon_256x256@2x.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_512x512.png" "$ICONSET_TMP/icon_512x512.png" 2>/dev/null || true
    cp "$ICONSET_SRC/icon_512x512@2x.png" "$ICONSET_TMP/icon_512x512@2x.png" 2>/dev/null || true
    
    iconutil -c icns "$ICONSET_TMP" -o "$RESOURCES_DIR/AppIcon.icns"
    rm -rf "$ICONSET_TMP"
fi

# Copy Syphon framework
SYPHON_FRAMEWORK="$SCRIPT_DIR/Frameworks/Syphon.xcframework/macos-arm64_x86_64/Syphon.framework"
if [ -d "$SYPHON_FRAMEWORK" ]; then
    echo "📚 Copying Syphon.framework..."
    mkdir -p "$CONTENTS_DIR/Frameworks"
    cp -R "$SYPHON_FRAMEWORK" "$CONTENTS_DIR/Frameworks/"
fi

echo "✅ App bundle created: $BUNDLE_DIR"
echo ""
echo "To run: open \"$BUNDLE_DIR\""
echo "To install: cp -R \"$BUNDLE_DIR\" /Applications/"
