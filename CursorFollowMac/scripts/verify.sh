#!/usr/bin/env bash
#
# verify.sh — developer verification of the release signature.
#
# Releases are signed with the self-signed identity from make_signing_cert.sh and are
# not notarized, so Gatekeeper (spctl) rejects them by design. This checks what we do
# control: the signature is valid, uses the expected identity and bundle ID, and has
# the hardened runtime and sandbox.
#
# Usage:
#   ./scripts/verify.sh [path-to-.app|.dmg]   # defaults to build/export/CursorFollowMac.app
#
# Exit code is non-zero if any check fails.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
require codesign

TARGET="${1:-$APP_PATH}"
[ -e "$TARGET" ] || die "not found: $TARGET"

fails=0
check() { if "$@"; then ok "$*"; else warn "FAILED: $*"; fails=$((fails+1)); fi; }
expect() {  # expect <description> <haystack> <needle>
  if grep -q -- "$3" <<<"$2"; then ok "$1"; else warn "FAILED: $1"; fails=$((fails+1)); fi
}

verify_app() {
  local app="$1" sig ents
  info "Verifying app bundle: $app"

  check codesign --verify --deep --strict --verbose=2 "$app"

  sig="$(codesign -dvv "$app" 2>&1)"
  echo "$sig" | grep -E '^(Identifier|Authority|Signature)=|flags=' | sed 's/^/    /'
  expect "bundle identifier = $APP_BUNDLE_ID" "$sig" "^Identifier=$APP_BUNDLE_ID\$"
  expect "hardened runtime enabled" "$sig" 'flags=.*runtime'
  if [ "$SIGN_IDENTITY" = "-" ]; then
    expect "ad-hoc signature" "$sig" '^Signature=adhoc'
  else
    expect "signed by \"$SIGN_IDENTITY\"" "$sig" "^Authority=$SIGN_IDENTITY\$"
  fi

  ents="$(codesign -d --entitlements - --xml "$app" 2>/dev/null || true)"
  expect "App Sandbox entitlement present" "$ents" 'com.apple.security.app-sandbox'
}

case "$TARGET" in
  *.app) verify_app "$TARGET" ;;
  *.dmg)
    info "Verifying DMG: $TARGET"
    check hdiutil verify -quiet "$TARGET"
    info "Mounting to verify the contained app"
    MNT="$(hdiutil attach "$TARGET" -nobrowse -readonly | grep '/Volumes/' | sed 's/.*\(\/Volumes\/.*\)/\1/' | tail -1)"
    if [ -n "${MNT:-}" ]; then
      INNER="$(/usr/bin/find "$MNT" -maxdepth 1 -name '*.app' | head -1)"
      if [ -n "$INNER" ]; then verify_app "$INNER"; else warn "FAILED: no .app in DMG"; fails=$((fails+1)); fi
      hdiutil detach "$MNT" >/dev/null 2>&1 || true
    else
      warn "FAILED: could not mount DMG"; fails=$((fails+1))
    fi
    ;;
  *) die "unsupported target: $TARGET" ;;
esac

echo
[ "$fails" -eq 0 ] && { ok "All verification checks passed"; exit 0; } || die "$fails check(s) failed"
