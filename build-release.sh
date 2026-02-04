#!/bin/bash
set -e

# Build configuration
APP_NAME="NexusHILBridge"
APP_DISPLAY_NAME="Nexus HIL Bridge"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"
DMG_NAME="NexusHILBridge-macOS"

echo "=== Building ${APP_NAME} v${VERSION} ==="

# Step 1: Build the executable
echo "Building executable..."
swift build --configuration release

# Step 2: Create app bundle structure
echo "Creating app bundle..."
rm -rf "${BUILD_DIR}/${APP_BUNDLE}"
mkdir -p "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${APP_BUNDLE}/Contents/Resources"

# Step 3: Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS/"
chmod +x "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Step 4: Copy Info.plist
cp "Resources/Info.plist" "${BUILD_DIR}/${APP_BUNDLE}/Contents/"

# Step 5: Create PkgInfo
echo -n "APPL????" > "${BUILD_DIR}/${APP_BUNDLE}/Contents/PkgInfo"

# Step 6: Create simple icon (placeholder - replace with actual icon)
# Using system icon as placeholder
if [ -f "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarAdvanced.icns" ]; then
    cp "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarAdvanced.icns" \
       "${BUILD_DIR}/${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "App bundle created at: ${BUILD_DIR}/${APP_BUNDLE}"

# Step 7: Create DMG
echo "Creating DMG..."
rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"

# Create temporary DMG directory
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

# Copy app to temp directory
cp -R "${BUILD_DIR}/${APP_BUNDLE}" "${DMG_TEMP}/"

# Create Applications symlink
ln -s /Applications "${DMG_TEMP}/Applications"

# Create DMG
hdiutil create -volname "${APP_DISPLAY_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${BUILD_DIR}/${DMG_NAME}.dmg"

# Cleanup
rm -rf "${DMG_TEMP}"

echo ""
echo "=== Build Complete ==="
echo "App Bundle: ${BUILD_DIR}/${APP_BUNDLE}"
echo "DMG: ${BUILD_DIR}/${DMG_NAME}.dmg"
echo ""

# Show DMG info
ls -lh "${BUILD_DIR}/${DMG_NAME}.dmg"
