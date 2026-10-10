#!/usr/bin/env bash
#
# package.sh — full release pipeline: build + sign -> DMG -> verify.
#
# Produces build/CursorFollowMac-<version>.dmg, signed with the self-signed release
# identity and NOT notarized. Users approve the first launch in System Settings →
# Privacy & Security → Open Anyway (see CursorFollowMac/README.md).
#
# Usage: ./scripts/package.sh

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

info "[1/3] Build + sign the app"
"$SCRIPT_DIR/build_release.sh"

info "[2/3] Build the DMG installer"
"$SCRIPT_DIR/make_dmg.sh" "$APP_PATH"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '0.0')"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VER.dmg"

info "[3/3] Verify"
"$SCRIPT_DIR/verify.sh" "$DMG_PATH"

echo
ok "Release ready: $DMG_PATH"
