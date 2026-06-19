#!/usr/bin/env bash
#
# package.sh — full release pipeline: build -> notarize app -> dmg -> notarize dmg.
#
# Produces a notarized, stapled, drag-to-install DMG ready to ship.
# This is the single command equivalent of "build the installer".
#
# Usage: ./scripts/package.sh

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

info "[1/4] Build + export Developer ID app"
"$SCRIPT_DIR/build_release.sh"

info "[2/4] Notarize + staple the .app (so it runs even if extracted from the DMG)"
"$SCRIPT_DIR/notarize.sh" "$APP_PATH"

info "[3/4] Build the DMG installer"
"$SCRIPT_DIR/make_dmg.sh" "$APP_PATH"

VER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo '0.0')"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VER.dmg"

info "[4/4] Notarize + staple the DMG"
"$SCRIPT_DIR/notarize.sh" "$DMG_PATH"

echo
ok "Release ready: $DMG_PATH"
info "Verify before shipping:  ./scripts/verify.sh \"$DMG_PATH\""
