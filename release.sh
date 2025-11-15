#!/bin/bash

# LunarBar Release Script
# Automates the process of building, packaging, and releasing a new version

set -e  # Exit on error

echo "🚀 LunarBar Release Script"
echo "=========================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Get version from Build.xcconfig
VERSION=$(grep "MARKETING_VERSION" Build.xcconfig | awk '{print $3}')
if [ -z "$VERSION" ]; then
    echo -e "${RED}❌ Failed to read version from Build.xcconfig${NC}"
    exit 1
fi

echo -e "${GREEN}📦 Version: ${VERSION}${NC}"
echo ""

DERIVED_DATA_DIR="$(pwd)/build/DerivedData"

# Check if tag already exists
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  Tag v${VERSION} already exists${NC}"
    read -p "Do you want to continue? This will overwrite the existing release. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi
fi

# Step 1: Close running app
echo "🛑 Closing running app..."
killall LunarBar 2>/dev/null || true
echo ""

# Step 2: Clean build
echo "🧹 Cleaning previous build..."
set +e
rm -rf "$DERIVED_DATA_DIR"
xcodebuild clean -project LunarBar.xcodeproj -scheme LunarBarMac -configuration Release -derivedDataPath "$DERIVED_DATA_DIR"
XC_CLEAN_STATUS=$?
set -e
if [ $XC_CLEAN_STATUS -ne 0 ]; then
    echo -e "${YELLOW}⚠️  Clean step reported non-zero exit status (${XC_CLEAN_STATUS}), continuing${NC}"
else
    echo -e "${GREEN}✓ Clean complete${NC}"
fi
echo ""

# Step 3: Build Release
echo "🔨 Building Release version..."
xcodebuild -project LunarBar.xcodeproj -scheme LunarBarMac -configuration Release build -derivedDataPath "$DERIVED_DATA_DIR" 2>&1 | grep -E "^\*\*|error:|warning:" || true
if [ ${PIPESTATUS[0]} -ne 0 ]; then
    echo -e "${RED}❌ Build failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Build complete${NC}"
echo ""

# Step 4: Create DMG
echo "📀 Creating DMG package..."
mkdir -p dist
rm -f "dist/LunarBar-${VERSION}.dmg"

APP_PATH="${DERIVED_DATA_DIR}/Build/Products/Release/LunarBar.app"
if [ ! -d "$APP_PATH" ]; then
    # Try to find the app in any DerivedData folder
    APP_PATH=$(find "$DERIVED_DATA_DIR" ~/Library/Developer/Xcode/DerivedData -name "LunarBar.app" -path "*/Build/Products/Release/*" 2>/dev/null | head -1)
    if [ -z "$APP_PATH" ]; then
        echo -e "${RED}❌ Could not find LunarBar.app${NC}"
        exit 1
    fi
fi

echo "🔏 Performing ad-hoc code signing for LunarBar.app (to satisfy Sparkle runtime checks)..."
if ! /usr/bin/codesign --force --deep --sign - "$APP_PATH" 2>/dev/null; then
  echo -e "${YELLOW}⚠️  Ad-hoc code signing failed; the app may still fail to load Sparkle at runtime${NC}"
fi
echo ""

# Create temporary directory for DMG contents
DMG_TEMP="dist/dmg_temp"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to temp directory
cp -R "$APP_PATH" "$DMG_TEMP/"

# Create symbolic link to Applications folder
ln -s /Applications "$DMG_TEMP/Applications"

# Create a writable DMG from temp directory
DMG_RW="dist/LunarBar-${VERSION}-temp.dmg"
FINAL_DMG="dist/LunarBar-${VERSION}.dmg"
rm -f "$DMG_RW" "$FINAL_DMG"
hdiutil create -volname "LunarBar" -srcfolder "$DMG_TEMP" -ov -format UDRW "$DMG_RW" > /dev/null

echo "🎨 Configuring DMG window layout..."
MOUNT_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW")
MOUNT_DEVICE=$(echo "$MOUNT_OUTPUT" | awk '/\/Volumes/ {print $1}')
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | awk '/\/Volumes/ {print $3}')

if [ -z "$MOUNT_DEVICE" ] || [ -z "$MOUNT_POINT" ]; then
    echo -e "${RED}❌ Failed to mount DMG for customization${NC}"
    exit 1
fi

/usr/bin/osascript <<'EOF'
tell application "Finder"
  tell disk "LunarBar"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 720, 420}
    set icon size of icon view options of container window to 120
    set arrangement of icon view options of container window to not arranged
    try
      set position of item "LunarBar.app" of container window to {170, 200}
    end try
    try
      set position of item "Applications" of container window to {500, 200}
    end try
    delay 1
    close
    delay 0.2
    open
    delay 1
    update without registering applications
  end tell
end tell
EOF

# Give Finder a moment to finish writing .DS_Store
sleep 2

# Clean up system artifact folders that may appear in the DMG root (best-effort)
if [ -n "$MOUNT_POINT" ] && [ -d "$MOUNT_POINT" ]; then
  rm -rf "$MOUNT_POINT/.fseventsd" "$MOUNT_POINT/.Trashes" 2>/dev/null || true
fi

# Detach the DMG and convert to compressed format
hdiutil detach "$MOUNT_POINT" > /dev/null
hdiutil convert "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG" > /dev/null
rm -f "$DMG_RW"

# Clean up temp directory
rm -rf "$DMG_TEMP"

DMG_SIZE=$(ls -lh "$FINAL_DMG" | awk '{print $5}')
echo -e "${GREEN}✓ DMG created: ${DMG_SIZE}${NC}"
echo ""

# Step 4.1: Create ZIP for Sparkle (optional)
echo "🗜️  Creating ZIP package for Sparkle..."
SPARKLE_ARCHIVES_DIR="dist/updates"
mkdir -p "$SPARKLE_ARCHIVES_DIR"
ZIP_PATH="${SPARKLE_ARCHIVES_DIR}/LunarBar-${VERSION}.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
ZIP_SIZE=$(ls -lh "$ZIP_PATH" | awk '{print $5}')
echo -e "${GREEN}✓ ZIP created: ${ZIP_SIZE}${NC}"
echo ""

# Step 4.2: Generate Sparkle appcast (if tools + signing key present)
APPCAST_PATH="${SPARKLE_ARCHIVES_DIR}/appcast.xml"

# Prefer developer tools from SPARKLE_BIN_DIR, fallback to generate_appcast in PATH
USE_APPCAST_TOOL=""
if [ -n "$SPARKLE_BIN_DIR" ] && [ -x "$SPARKLE_BIN_DIR/generate_appcast" ]; then
  USE_APPCAST_TOOL="$SPARKLE_BIN_DIR/generate_appcast"
elif command -v generate_appcast >/dev/null 2>&1; then
  USE_APPCAST_TOOL="generate_appcast"
fi

if [ -n "$USE_APPCAST_TOOL" ]; then
  echo "📰 Generating Sparkle appcast.xml using: $USE_APPCAST_TOOL"
  if [ -n "$SPARKLE_PRIVATE_KEY_FILE" ] && [ -f "$SPARKLE_PRIVATE_KEY_FILE" ]; then
    # Use explicit private key file if provided (CI / advanced setups)
    "$USE_APPCAST_TOOL" --ed-key-file "$SPARKLE_PRIVATE_KEY_FILE" -o "$APPCAST_PATH" "$SPARKLE_ARCHIVES_DIR"
  else
    # Otherwise rely on the EdDSA key stored in the user's Keychain (recommended local setup)
    "$USE_APPCAST_TOOL" -o "$APPCAST_PATH" "$SPARKLE_ARCHIVES_DIR"
  fi
  echo -e "${GREEN}✓ Appcast generated at ${APPCAST_PATH}${NC}"

  echo "🌐 Publishing appcast to gh-pages..."
  set +e
  git fetch origin gh-pages 2>/dev/null
  set -e
  rm -rf build/gh-pages
  if git show-ref --verify --quiet refs/remotes/origin/gh-pages; then
    git worktree add -B gh-pages build/gh-pages origin/gh-pages
  else
    git worktree add -B gh-pages build/gh-pages
  fi
  mkdir -p build/gh-pages
  cp -f "$APPCAST_PATH" build/gh-pages/appcast.xml
  # Also publish Sparkle update archives alongside appcast.xml
  cp -f "$SPARKLE_ARCHIVES_DIR"/* build/gh-pages/ 2>/dev/null || true
  pushd build/gh-pages >/dev/null
  git add appcast.xml *.zip 2>/dev/null || git add appcast.xml
  if ! git diff --cached --quiet; then
    git -c user.name="Tbxhs" -c user.email="Tbxhs@users.noreply.github.com" commit -m "docs(appcast): ${VERSION}"
    git push origin gh-pages
    echo -e "${GREEN}✓ Appcast published to gh-pages${NC}"
  else
    echo "Appcast unchanged; skip publishing"
  fi
  popd >/dev/null
else
  echo -e "${YELLOW}⚠️  Sparkle developer tools not found; skip appcast generation${NC}"
  echo "   To enable signing locally:"
  echo "   1) Install Sparkle developer tools (contains 'generate_appcast' & 'sign_update'):"
  echo "      https://github.com/sparkle-project/Sparkle/releases or 'brew install --cask sparkle'"
  echo "   2) Ensure 'generate_appcast' is either in SPARKLE_BIN_DIR or in your PATH."
  echo "   3) Optionally set SPARKLE_PRIVATE_KEY_FILE to a private key file if you are not using the Keychain."
  echo "   Then rerun ./release.sh"
fi

# Step 5: Create Git tag
echo "🏷️  Creating Git tag..."
git tag -fa "v${VERSION}" -m "Release ${VERSION}"
git push origin "v${VERSION}" --force
echo -e "${GREEN}✓ Tag v${VERSION} pushed${NC}"
echo ""

# Step 6: Create GitHub Release
echo "📝 Creating GitHub Release..."

# Extract changelog for this version
# Use awk to extract content between version headers, excluding the headers themselves
CHANGELOG=$(awk "
  /^## \[${VERSION}\]/ { flag=1; next }
  /^## \[/ { if (flag) exit }
  flag && !/^$/ && !/^#/ { print }
" CHANGELOG.md)

# Fallback if extraction fails
if [ -z "$CHANGELOG" ]; then
    CHANGELOG="Release ${VERSION}"
fi

# Check if gh is authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  GitHub CLI not authenticated${NC}"
    echo "Please run: gh auth login"
    echo ""
    echo "Then manually create the release at:"
    echo "https://github.com/Tbxhs/LunarBar/releases/new?tag=v${VERSION}&title=${VERSION}"
    echo ""
    echo "And upload: dist/LunarBar-${VERSION}.dmg"
    exit 0
fi

# Delete existing release if it exists
gh release delete "v${VERSION}" --yes --repo Tbxhs/LunarBar 2>/dev/null || true

# Create new release
gh release create "v${VERSION}" \
    --title "${VERSION}" \
    --notes "${CHANGELOG}" \
    --repo Tbxhs/LunarBar \
    "dist/LunarBar-${VERSION}.dmg" \
    "dist/updates/LunarBar-${VERSION}.zip"

echo -e "${GREEN}✓ Release published${NC}"
echo ""

# Step 7: Done!
echo -e "${GREEN}✨ Release ${VERSION} complete!${NC}"
echo ""
echo "🔗 View release: https://github.com/Tbxhs/LunarBar/releases/tag/v${VERSION}"
echo ""

echo "ℹ️  Sparkle setup next steps (once):"
echo "   1) Generate EdDSA keys and add SUPublicEDKey to Info.plist"
echo "   2) Sign the ZIP with Sparkle's sign_update, and generate appcast.xml"
echo "   3) Host appcast.xml over HTTPS (e.g., GitHub Pages) and set SUFeedURL"
echo "   4) Then Sparkle will offer Install/Update in-app"
