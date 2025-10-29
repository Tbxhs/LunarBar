# Release Guide

## Quick Release

To release a new version of LunarBar:

### 1. Update Version Number

Edit `Build.xcconfig` and bump the version:

```
MARKETING_VERSION = 1.9.2
CURRENT_PROJECT_VERSION = 20
```

### 2. Update Changelog

Add your changes to `CHANGELOG.md`:

```markdown
## [1.9.2] - 2025-06-14
- Your new features
- Bug fixes
- Improvements
```

### 3. Commit Changes

```bash
git add Build.xcconfig CHANGELOG.md
git commit -m "Bump version to 1.9.2"
git push origin main
```

### 4. Run Release Script

```bash
./release.sh
```

This will automatically:
- ✅ Clean and build Release version
- ✅ Create DMG installer (in `dist/` folder)
- ✅ Create and push Git tag
- ✅ Create GitHub Release with DMG attachment

---

## First Time Setup

### Authenticate GitHub CLI

The release script uses GitHub CLI to create releases. First time you need to authenticate:

```bash
gh auth login
```

Choose:
- **What account do you want to log into?** → GitHub.com
- **What is your preferred protocol for Git operations?** → SSH
- **How would you like to authenticate GitHub CLI?** → Login with a web browser

Then follow the browser prompts.

---

## Manual Release (If Script Fails)

If the automated script doesn't work, you can release manually:

### 1. Build DMG

```bash
# Clean
xcodebuild clean -project LunarBar.xcodeproj -scheme LunarBarMac -configuration Release

# Build
xcodebuild -project LunarBar.xcodeproj -scheme LunarBarMac -configuration Release build

# Create DMG
mkdir -p dist
VERSION=$(grep "MARKETING_VERSION" Build.xcconfig | awk '{print $3}')
hdiutil create -volname "LunarBar" \
  -srcfolder ~/Library/Developer/Xcode/DerivedData/LunarBar-*/Build/Products/Release/LunarBar.app \
  -ov -format UDZO "dist/LunarBar-${VERSION}.dmg"
```

### 2. Create Tag

```bash
VERSION=$(grep "MARKETING_VERSION" Build.xcconfig | awk '{print $3}')
git tag "v${VERSION}"
git push origin "v${VERSION}"
```

### 3. Create Release

Visit: https://github.com/Tbxhs/LunarBar/releases/new

- **Choose a tag**: v1.9.2
- **Release title**: 1.9.2 (⚠️ no "v" prefix!)
- **Description**: Copy from CHANGELOG.md
- **Attach binary**: Upload `dist/LunarBar-1.9.2.dmg`
- Click **Publish release**

---

## Troubleshooting

### Build fails

```bash
# Reset DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/LunarBar-*

# Try building in Xcode first to see detailed errors
open LunarBar.xcodeproj
```

### GitHub CLI authentication issues

```bash
# Check status
gh auth status

# Re-authenticate
gh auth logout
gh auth login
```

### Tag already exists

If you need to overwrite a tag:

```bash
# Delete local tag
git tag -d v1.9.2

# Delete remote tag
git push --delete origin v1.9.2

# Create new tag
git tag v1.9.2
git push origin v1.9.2
```

---

## AppUpdater Configuration

The app's auto-updater is configured to check:
- **API**: `https://api.github.com/repos/Tbxhs/LunarBar/releases/latest`
- **Version matching**: Compares GitHub release title with `MARKETING_VERSION`

**Important**: The GitHub release **title** must match `MARKETING_VERSION` exactly (no "v" prefix).

Example:
- ✅ Tag: `v1.9.2`, Title: `1.9.2` ← Correct
- ❌ Tag: `v1.9.2`, Title: `v1.9.2` ← Wrong (updater won't detect)
