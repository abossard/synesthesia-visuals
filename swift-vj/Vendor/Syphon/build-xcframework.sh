#!/bin/bash
# Build Syphon.xcframework from Syphon-Framework source
# This script downloads, builds, and packages Syphon for SPM

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
OUTPUT_DIR="${SCRIPT_DIR}"
SYPHON_REPO="https://github.com/Syphon/Syphon-Framework.git"
SYPHON_BRANCH="master"

# Cleanup
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

echo "==> Cloning Syphon-Framework..."
git clone --depth 1 --branch "${SYPHON_BRANCH}" "${SYPHON_REPO}" Syphon-Framework

cd Syphon-Framework

echo "==> Building Syphon.framework for macOS (arm64 + x86_64)..."

# Build for arm64
xcodebuild archive \
    -project Syphon.xcodeproj \
    -scheme Syphon \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "${BUILD_DIR}/Syphon-macOS.xcarchive" \
    SKIP_INSTALL=NO \
    BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64 x86_64" \
    2>&1 | grep -E "(error:|warning:|BUILD|ARCHIVE)"

# Verify the archive
if [ ! -d "${BUILD_DIR}/Syphon-macOS.xcarchive" ]; then
    echo "Error: Archive not created. Trying alternate build..."

    # Alternative: Direct build
    xcodebuild build \
        -project Syphon.xcodeproj \
        -scheme Syphon \
        -configuration Release \
        -derivedDataPath "${BUILD_DIR}/DerivedData" \
        ARCHS="arm64 x86_64" \
        ONLY_ACTIVE_ARCH=NO \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES

    FRAMEWORK_PATH="${BUILD_DIR}/DerivedData/Build/Products/Release/Syphon.framework"
else
    FRAMEWORK_PATH="${BUILD_DIR}/Syphon-macOS.xcarchive/Products/Library/Frameworks/Syphon.framework"
fi

echo "==> Creating xcframework..."

# Create xcframework
xcodebuild -create-xcframework \
    -framework "${FRAMEWORK_PATH}" \
    -output "${OUTPUT_DIR}/Syphon.xcframework"

echo "==> Cleaning up..."
rm -rf "${BUILD_DIR}"

echo "==> Done! Syphon.xcframework created at ${OUTPUT_DIR}/Syphon.xcframework"
echo ""
echo "To use in Package.swift, add:"
echo '    .binaryTarget('
echo '        name: "Syphon",'
echo '        path: "Vendor/Syphon/Syphon.xcframework"'
echo '    )'
