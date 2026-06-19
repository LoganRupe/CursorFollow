#!/usr/bin/env bash
#
# make_dmg.sh — build a drag-to-Applications DMG: the macOS "installer".
#
# On macOS the idiomatic installer for a Developer ID app (especially one that
# activates a system extension) is a DMG containing the .app plus an
# /Applications symlink. The user drags the app over, which also satisfies the
# "must run from /Applications" requirement for system-extension activation.
#
# Usage: ./scripts/make_dmg.sh [path-to-.app]
#   defaults to build/export/CursorFollowMac.app

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
require hdiutil

SRC_APP="${1:-$APP_PATH}"
[ -d "$SRC_APP" ] || die "app not found: $SRC_APP (run ./scripts/build_release.sh first)"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SRC_APP/Contents/Info.plist" 2>/dev/null || echo '0.0')"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VER.dmg"
STAGE="$BUILD_DIR/dmg-stage"

# Prefer create-dmg (nicer layout/background) if the operator has it installed.
if command -v create-dmg >/dev/null 2>&1; then
  info "Building DMG with create-dmg"
  rm -f "$DMG_PATH"
  create-dmg \
    --volname "$APP_NAME $VER" \
    --app-drop-link 450 180 \
    --icon "$APP_NAME.app" 150 180 \
    --window-size 600 360 \
    "$DMG_PATH" "$SRC_APP" || die "create-dmg failed"
  ok "Built $DMG_PATH"
  exit 0
fi

info "Building DMG with hdiutil (install create-dmg for a fancier layout)"
rm -rf "$STAGE" "$DMG_PATH"
mkdir -p "$STAGE"
/bin/cp -R "$SRC_APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "$APP_NAME $VER" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "$DMG_PATH"

rm -rf "$STAGE"
ok "Built $DMG_PATH"
info "Next: ./scripts/notarize.sh \"$DMG_PATH\""
