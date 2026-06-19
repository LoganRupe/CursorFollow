#!/usr/bin/env bash
#
# notarize.sh — submit an artifact to Apple notarization and staple the ticket.
#
# macOS analog of "get the signature trusted so Gatekeeper/SmartScreen won't warn".
# Works on a .app (zipped for submission) or a .dmg/.pkg (submitted directly).
#
# Usage: ./scripts/notarize.sh <path-to-.app|.dmg|.pkg>
#
# Requires a one-time credential setup:
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#     --apple-id you@example.com --team-id YOURTEAMID --password <app-specific-password>
# (App-specific password from appleid.apple.com, NOT your Apple ID password.)

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
require xcrun

TARGET="${1:-}"
[ -n "$TARGET" ] || die "usage: $0 <path-to-.app|.dmg|.pkg>"
[ -e "$TARGET" ] || die "not found: $TARGET"

submit() {
  info "Submitting $(basename "$1") to notarization (this can take a few minutes)"
  xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait
}

case "$TARGET" in
  *.app)
    ZIP="${TARGET%.app}.zip"
    info "Zipping app for submission"
    rm -f "$ZIP"
    /usr/bin/ditto -c -k --keepParent "$TARGET" "$ZIP"
    submit "$ZIP"
    rm -f "$ZIP"
    info "Stapling ticket onto the .app"
    xcrun stapler staple "$TARGET"
    ;;
  *.dmg|*.pkg)
    submit "$TARGET"
    info "Stapling ticket onto $(basename "$TARGET")"
    xcrun stapler staple "$TARGET"
    ;;
  *)
    die "unsupported artifact: $TARGET (expected .app/.dmg/.pkg)"
    ;;
esac

xcrun stapler validate "$TARGET" >/dev/null && ok "Notarized + stapled: $TARGET"
