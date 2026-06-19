#!/usr/bin/env bash
#
# build_release.sh — archive CursorFollowMac and export a Developer ID signed .app.
#
# This is the macOS analog of "produce the release binary the installer wraps".
# Output: build/export/CursorFollowMac.app (Developer ID signed, hardened runtime).
#
# Usage: ./scripts/build_release.sh

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
require xcodebuild

info "Cleaning previous archive/export"
rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"
mkdir -p "$BUILD_DIR"

info "Archiving $SCHEME (Release, Developer ID)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  archive

info "Exporting Developer ID app from archive"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

[ -d "$APP_PATH" ] || die "expected app not found at $APP_PATH"

# Surface the version so the operator can confirm the upgrade bump landed.
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '?')"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '?')"
ok "Exported $APP_PATH (version $VER build $BUILD)"
info "Next: ./scripts/notarize.sh \"$APP_PATH\"  (or run ./scripts/package.sh for the full pipeline)"
