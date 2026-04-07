#!/bin/bash
# create-dmg.sh - Package a .app into a distributable DMG
#
# Usage:
#   ./create-dmg.sh                                              # Defaults
#   ./create-dmg.sh --app-path "Swift VJ.app" --output SwiftVJ-1.0.0.dmg

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/Swift VJ.app"
OUTPUT="$SCRIPT_DIR/SwiftVJ.dmg"
VOLUME_NAME="Swift VJ"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app-path)
            APP_PATH="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --volume-name)
            VOLUME_NAME="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--app-path PATH] [--output PATH] [--volume-name NAME]"
            exit 1
            ;;
    esac
done

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at: $APP_PATH"
    echo "Run bundle-app.sh first."
    exit 1
fi

echo "Creating DMG from: $APP_PATH"

# Create staging directory
STAGING_DIR=$(mktemp -d)
trap 'rm -rf "$STAGING_DIR"' EXIT

# Copy app and create Applications symlink for drag-to-install
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

# Remove existing DMG if present
rm -f "$OUTPUT"

# Create compressed read-only DMG
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$OUTPUT"

echo ""
echo "DMG created: $OUTPUT"
ls -lh "$OUTPUT"
