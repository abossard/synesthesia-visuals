#!/bin/bash
# Build and codesign VDJStatus CLI for Screen Recording access

set -e

cd "$(dirname "$0")"

echo "Building vdjstatus..."
swift build -c release

BINARY=".build/release/vdjstatus"
ENTITLEMENTS="Sources/VDJStatusCLI/vdjstatus.entitlements"

echo "Codesigning with entitlements..."
codesign --force --sign - --entitlements "$ENTITLEMENTS" "$BINARY"

echo ""
echo "✓ Build complete: $BINARY"
echo ""
echo "To install globally:"
echo "  sudo cp $BINARY /usr/local/bin/"
echo ""
echo "Note: First run will prompt for Screen Recording permission."
echo "      Grant access in System Settings > Privacy & Security > Screen Recording"
