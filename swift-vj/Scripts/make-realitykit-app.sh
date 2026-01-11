#!/bin/bash
# make-realitykit-app.sh - Bundle RealityKit VJ Kitchen Sink as .app
# Creates a runnable macOS application bundle from SPM build

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_NAME="RealityKitVJKitchenSink"
BUNDLE_DIR="$SCRIPT_DIR/Build/$APP_NAME.app"
CONTENTS_DIR="$BUNDLE_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"

echo "🔨 Building RealityKitVJKitchenSink (release)..."
cd "$SCRIPT_DIR"
swift build --target RealityKitVJKitchenSink -c release

echo "📦 Creating app bundle: $APP_NAME.app"

# Clean and create bundle structure
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

# Copy executable
cp "$BUILD_DIR/RealityKitVJKitchenSink" "$MACOS_DIR/RealityKitVJKitchenSink"

# Copy resources from bundle (if any)
if [ -d "$BUILD_DIR/RealityKitVJKitchenSink_RealityKitVJKitchenSink.bundle" ]; then
    cp -R "$BUILD_DIR/RealityKitVJKitchenSink_RealityKitVJKitchenSink.bundle/"* "$RESOURCES_DIR/" 2>/dev/null || true
fi

# Copy Syphon framework
SYPHON_FRAMEWORK="$SCRIPT_DIR/Frameworks/Syphon.xcframework/macos-arm64_x86_64/Syphon.framework"
if [ -d "$SYPHON_FRAMEWORK" ]; then
    echo "📚 Copying Syphon.framework..."
    cp -R "$SYPHON_FRAMEWORK" "$FRAMEWORKS_DIR/"
else
    echo "⚠️  Syphon framework not found at: $SYPHON_FRAMEWORK"
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
    <string>RealityKitVJKitchenSink</string>
    <key>CFBundleIdentifier</key>
    <string>com.synesthesia.RealityKitVJKitchenSink</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>RealityKit VJ Kitchen Sink</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "✅ App bundle created: $BUNDLE_DIR"
echo ""
echo "To run:    open \"$BUNDLE_DIR\""
echo "To test:   \"$BUNDLE_DIR/Contents/MacOS/RealityKitVJKitchenSink\""
echo "To install: cp -R \"$BUNDLE_DIR\" /Applications/"
