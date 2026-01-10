#!/bin/bash
# make-realitykit-app.sh
# Builds and bundles the RealityKitVJKitchenSink app

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/Build"
APP_NAME="RealityKitVJKitchenSink"
BUNDLE_ID="com.swiftvj.realitykit-kitchen-sink"

echo "================================================"
echo "Building $APP_NAME"
echo "================================================"

# Navigate to project directory
cd "$PROJECT_DIR"

# Build in release mode
echo "Building with Swift Package Manager..."
swift build -c release --product "$APP_NAME"

# Create build output directory
mkdir -p "$BUILD_DIR"

# Create app bundle structure
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Copy executable
echo "Creating app bundle..."
cp ".build/release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy Syphon framework
if [ -d "Frameworks/Syphon.xcframework/macos-arm64_x86_64/Syphon.framework" ]; then
    cp -R "Frameworks/Syphon.xcframework/macos-arm64_x86_64/Syphon.framework" "$APP_BUNDLE/Contents/Frameworks/"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
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
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Fix library paths
echo "Fixing library paths..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_BUNDLE/Contents/MacOS/$APP_NAME" 2>/dev/null || true

# Sign the app (ad-hoc for local use)
echo "Signing app bundle..."
codesign --deep --force --sign - "$APP_BUNDLE" 2>/dev/null || echo "Signing skipped (no code signing identity)"

echo ""
echo "================================================"
echo "Build complete!"
echo "================================================"
echo ""
echo "App bundle: $APP_BUNDLE"
echo ""
echo "To run:"
echo "  open \"$APP_BUNDLE\""
echo ""
echo "Or from command line:"
echo "  swift run $APP_NAME"
echo ""
