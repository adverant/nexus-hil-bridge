#!/bin/bash
set -e

# =============================================================================
# Adverant Nexus EE HIL Bridge - Build Script
# =============================================================================

# Build configuration
APP_NAME="AdverantNexusEEHILBridge"
APP_DISPLAY_NAME="Adverant Nexus EE HIL Bridge"
VERSION="1.0.0"
BUILD_NUMBER="100"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_DISPLAY_NAME}.app"
DMG_NAME="Adverant-Nexus-EE-HIL-Bridge-${VERSION}-macOS"

echo "=============================================="
echo "Building ${APP_DISPLAY_NAME} v${VERSION}"
echo "=============================================="

# Step 1: Clean previous builds
echo ""
echo "=== Step 1: Cleaning previous builds ==="
rm -rf "${BUILD_DIR}/${APP_BUNDLE}" 2>/dev/null || true
rm -rf "${BUILD_DIR}/${DMG_NAME}.dmg" 2>/dev/null || true
swift package clean 2>/dev/null || true
echo "✓ Cleaned"

# Step 2: Build the executable
echo ""
echo "=== Step 2: Building executable ==="
swift build --configuration release
echo "✓ Build complete"

# Step 3: Create app bundle structure
echo ""
echo "=== Step 3: Creating app bundle ==="
mkdir -p "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${BUILD_DIR}/${APP_BUNDLE}/Contents/Resources"

# Step 4: Copy executable
cp "${BUILD_DIR}/${APP_NAME}" "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS/"
chmod +x "${BUILD_DIR}/${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# Step 5: Copy Info.plist
cp "Resources/Info.plist" "${BUILD_DIR}/${APP_BUNDLE}/Contents/"

# Step 6: Create PkgInfo
echo -n "APPL????" > "${BUILD_DIR}/${APP_BUNDLE}/Contents/PkgInfo"

# Step 7: Create app icon (using system icon as placeholder)
if [ -f "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarAdvanced.icns" ]; then
    cp "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/ToolbarAdvanced.icns" \
       "${BUILD_DIR}/${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
fi

echo "✓ App bundle created: ${APP_BUNDLE}"

# Step 8: Ad-hoc code sign the app
echo ""
echo "=== Step 4: Code signing ==="
codesign --force --deep --sign - "${BUILD_DIR}/${APP_BUNDLE}" 2>/dev/null || echo "⚠ Code signing skipped (no signing identity)"
echo "✓ Code signing complete"

# Step 9: Create DMG
echo ""
echo "=== Step 5: Creating DMG ==="

# Remove old DMG if exists
rm -f "${BUILD_DIR}/${DMG_NAME}.dmg"

# Create temporary DMG directory
DMG_TEMP="${BUILD_DIR}/dmg_temp"
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

# Copy app to temp directory
cp -R "${BUILD_DIR}/${APP_BUNDLE}" "${DMG_TEMP}/"

# Create Applications symlink
ln -s /Applications "${DMG_TEMP}/Applications"

# Create a README file
cat > "${DMG_TEMP}/README.txt" << 'EOF'
Adverant Nexus EE HIL Bridge
============================

Installation:
1. Drag "Adverant Nexus EE HIL Bridge" to the Applications folder
2. Launch from Applications or Spotlight
3. The app will appear in your menubar (top-right)

IMPORTANT - First Launch (macOS Security):
-------------------------------------------
macOS will show a security warning because the app isn't from the App Store.
To open it:

Method 1 (Recommended):
  1. Right-click (or Control-click) on the app in Applications
  2. Select "Open" from the menu
  3. Click "Open" in the dialog

Method 2:
  1. Go to System Settings → Privacy & Security
  2. Scroll to Security section
  3. Click "Open Anyway" next to the blocked app name

Usage:
1. Connect your hardware instruments via USB
2. Open https://nexus.adverant.ai
3. Navigate to EE Design Partner → Projects → HIL Testing
4. The dashboard will automatically detect your bridge

Support:
- Documentation: https://docs.adverant.ai/hil-bridge
- Issues: https://github.com/adverant/nexus-hil-bridge/issues
- Email: support@adverant.ai

Version: 1.0.0
Copyright © 2026 Adverant AI
EOF

# Create the DMG using hdiutil with proper settings
echo "Creating DMG file..."
hdiutil create \
    -volname "${APP_DISPLAY_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov \
    -format UDBZ \
    -fs HFS+ \
    "${BUILD_DIR}/${DMG_NAME}.dmg"

# Cleanup temp directory
rm -rf "${DMG_TEMP}"

echo ""
echo "=============================================="
echo "BUILD COMPLETE"
echo "=============================================="
echo ""
echo "App Bundle: ${BUILD_DIR}/${APP_BUNDLE}"
echo "DMG File:   ${BUILD_DIR}/${DMG_NAME}.dmg"
echo ""
echo "DMG Info:"
ls -lh "${BUILD_DIR}/${DMG_NAME}.dmg"
echo ""
echo "To install locally:"
echo "  open \"${BUILD_DIR}/${DMG_NAME}.dmg\""
echo ""
echo "Or copy directly to Applications:"
echo "  cp -R \"${BUILD_DIR}/${APP_BUNDLE}\" /Applications/"
echo ""
