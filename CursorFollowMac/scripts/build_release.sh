#!/usr/bin/env bash
#
# build_release.sh — build CursorFollowMac (Release) and sign it with the release identity.
#
# Output: build/export/CursorFollowMac.app, signed with $SIGN_IDENTITY, hardened runtime.
# Not notarized: users approve the first launch in System Settings → Privacy & Security.
#
# Xcode builds with an ad-hoc signature (the project has no team), then this script
# re-signs with the self-signed identity, keeping the entitlements Xcode generated
# (App Sandbox comes from the ENABLE_APP_SANDBOX build setting, not the .entitlements file).
#
# Usage: ./scripts/build_release.sh

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
require xcodebuild
require codesign

if [ "$SIGN_IDENTITY" != "-" ] && ! security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
  die "signing identity \"$SIGN_IDENTITY\" not found; run ./scripts/make_signing_cert.sh (or SIGN_IDENTITY=- for ad-hoc)"
fi

info "Cleaning previous build"
rm -rf "$DERIVED_DATA" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

info "Building $SCHEME (Release, universal)"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  ONLY_ACTIVE_ARCH=NO \
  build

BUILT_APP="$DERIVED_DATA/Build/Products/Release/$APP_NAME.app"
[ -d "$BUILT_APP" ] || die "expected app not found at $BUILT_APP"
/bin/cp -R "$BUILT_APP" "$APP_PATH"

info "Signing with \"$SIGN_IDENTITY\""
ENTITLEMENTS="$BUILD_DIR/entitlements.plist"
codesign -d --entitlements - --xml "$APP_PATH" > "$ENTITLEMENTS" 2>/dev/null
codesign --force --timestamp=none --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGN_IDENTITY" \
  "$APP_PATH"
rm -f "$ENTITLEMENTS"

# Surface the version so the operator can confirm the upgrade bump landed.
VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '?')"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '?')"
ok "Built $APP_PATH (version $VER build $BUILD)"
info "Next: ./scripts/make_dmg.sh  (or run ./scripts/package.sh for the full pipeline)"
