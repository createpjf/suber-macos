#!/bin/bash
set -e

# Configuration
APP_NAME="SubReminder"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-${VERSION}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
DMG_DIR="${BUILD_DIR}/dmg"
OUTPUT_DMG="${PROJECT_DIR}/${DMG_NAME}.dmg"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Clean previous build
rm -rf "${BUILD_DIR}"
rm -f "${OUTPUT_DMG}"

# Step 1: Build Release
echo ">> Building Release..."
xcodebuild build \
    -project "${PROJECT_DIR}/SubReminder.xcodeproj" \
    -scheme SubReminder \
    -configuration Release \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    -destination 'platform=macOS' \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    2>&1 | tail -5

APP_PATH="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "${APP_PATH}" ]; then
    echo "ERROR: Build failed - ${APP_PATH} not found"
    exit 1
fi

echo ">> Build successful: ${APP_PATH}"

# Step 2: Prepare DMG contents
echo ">> Preparing DMG contents..."
mkdir -p "${DMG_DIR}"
cp -R "${APP_PATH}" "${DMG_DIR}/"

# Create symlink to /Applications for drag-install
ln -s /Applications "${DMG_DIR}/Applications"

# Step 3: Create DMG
echo ">> Creating DMG..."
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_DIR}" \
    -ov \
    -format UDZO \
    "${OUTPUT_DMG}"

# Clean up
rm -rf "${BUILD_DIR}"

echo ""
echo "=== Done ==="
echo "DMG: ${OUTPUT_DMG}"
echo "Size: $(du -h "${OUTPUT_DMG}" | cut -f1)"
