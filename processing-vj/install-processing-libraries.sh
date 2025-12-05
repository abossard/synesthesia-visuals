#!/bin/bash
# Install Processing libraries required for CI testing
# 
# This script installs all Processing libraries needed by the sketches
# in this repository. It can be run locally or in CI.
#
# Usage: ./install-processing-libraries.sh [sketchbook_path]
#
# If sketchbook_path is not provided, uses ~/sketchbook

set -e

SKETCHBOOK="${1:-$HOME/sketchbook}"
LIBS_DIR="$SKETCHBOOK/libraries"

echo "Installing Processing libraries to: $LIBS_DIR"
echo ""

# Create libraries directory
mkdir -p "$LIBS_DIR"

# Function to download and install a library
install_library() {
    local name="$1"
    local url="$2"
    local zip_file=$(basename "$url")
    
    if [ -d "$LIBS_DIR/$name" ]; then
        echo "✓ $name already installed"
        return 0
    fi
    
    echo "Installing $name..."
    wget -q "$url" -O "/tmp/$zip_file"
    unzip -q "/tmp/$zip_file" -d "$LIBS_DIR/"
    rm "/tmp/$zip_file"
    echo "✅ $name installed"
}

# Install oscP5 (provides both oscP5 and netP5)
install_library "oscP5" "https://github.com/sojamo/oscp5/releases/download/v2.0.4/oscP5-2.0.4.zip"

# Install The MidiBus
install_library "themidibus" "https://github.com/sparks/themidibus/releases/download/v9/themidibus.zip"

# Install Processing Sound library
if [ ! -d "$LIBS_DIR/sound" ]; then
    echo "Installing Processing Sound library..."
    
    # Try to download from GitHub releases
    if wget -q https://github.com/processing/processing-sound/releases/download/latest/sound.zip -O /tmp/sound.zip 2>/dev/null; then
        unzip -q /tmp/sound.zip -d "$LIBS_DIR/"
        rm /tmp/sound.zip
        echo "✅ Sound library installed"
    else
        echo "⚠️  Could not download Sound library - may need to install via Processing IDE"
        echo "   In Processing: Sketch → Import Library → Manage Libraries → Search 'Sound'"
    fi
else
    echo "✓ Sound library already installed"
fi

# Note about Syphon (macOS only)
echo ""
echo "Note: Syphon library is macOS-only and cannot be installed on Linux."
echo "On macOS, install it via Processing IDE:"
echo "  Sketch → Import Library → Manage Libraries → Search 'Syphon'"
echo ""

echo "Library installation complete!"
echo ""
echo "Installed libraries:"
ls -1 "$LIBS_DIR/"
