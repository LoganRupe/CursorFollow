#!/usr/bin/env bash
#
# verify.sh — developer verification of signing / hardened runtime / notarization.
#
# macOS analog of `signtool verify` + `Get-AuthenticodeSignature`. Run this before
# shipping and after install to confirm Gatekeeper will accept the build.
#
# Usage:
#   ./scripts/verify.sh [path-to-.app|.dmg]   # defaults to build/export/CursorFollowMac.app
#
# Exit code is non-zero if any check fails.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
require codesign
require spctl

TARGET="${1:-$APP_PATH}"
[ -e "$TARGET" ] || die "not found: $TARGET"

fails=0
check() { if "$@"; then ok "$*"; else warn "FAILED: $*"; fails=$((fails+1)); fi; }

verify_app() {
  local app="$1"
  info "Verifying app bundle: $app"

  # 1. Code signature is valid, deep, and strict (covers embedded extension).
  check codesign --verify --deep --strict --verbose=2 "$app"

  # 2. Signed by Developer ID + hardened runtime flag present.
  info "Signature authority + flags:"
  codesign -dvv "$app" 2>&1 | grep -E 'Authority|TeamIdentifier|flags|Identifier=' || true
  if codesign -dvv "$app" 2>&1 | grep -q 'flags=.*runtime'; then
    ok "hardened runtime enabled"
  else
    warn "FAILED: hardened runtime flag not set (notarization will reject)"; fails=$((fails+1))
  fi
  if codesign -dvv "$app" 2>&1 | grep -q "TeamIdentifier=$TEAM_ID"; then
    ok "team identifier = $TEAM_ID"
  else
    warn "FAILED: unexpected team identifier"; fails=$((fails+1))
  fi

  # 3. Gatekeeper assessment (requires notarization ticket to pass).
  check spctl -a -vvv -t exec "$app"

  # 4. Notarization ticket stapled?
  if xcrun stapler validate "$app" >/dev/null 2>&1; then
    ok "notarization ticket stapled"
  else
    warn "no stapled ticket (run ./scripts/notarize.sh) — Gatekeeper will need online check"
  fi

  # 5. No system extension should be embedded (CameraExtension was removed).
  local ext
  ext="$(/usr/bin/find "$app/Contents/Library/SystemExtensions" -maxdepth 1 -name '*.systemextension' 2>/dev/null | head -1)"
  if [ -n "$ext" ]; then
    warn "FAILED: unexpected embedded system extension: $(basename "$ext")"; fails=$((fails+1))
  else
    ok "no embedded system extension (expected)"
  fi
}

case "$TARGET" in
  *.app) verify_app "$TARGET" ;;
  *.dmg)
    info "Verifying DMG: $TARGET"
    check spctl -a -vvv -t open --context context:primary-signature "$TARGET"
    if xcrun stapler validate "$TARGET" >/dev/null 2>&1; then ok "DMG ticket stapled"; else warn "DMG not stapled"; fi
    info "Mounting to verify the contained app"
    MNT="$(hdiutil attach "$TARGET" -nobrowse -readonly | grep '/Volumes/' | sed 's/.*\(\/Volumes\/.*\)/\1/' | tail -1)"
    if [ -n "${MNT:-}" ]; then
      INNER="$(/usr/bin/find "$MNT" -maxdepth 1 -name '*.app' | head -1)"
      [ -n "$INNER" ] && verify_app "$INNER"
      hdiutil detach "$MNT" >/dev/null 2>&1 || true
    fi
    ;;
  *) die "unsupported target: $TARGET" ;;
esac

echo
[ "$fails" -eq 0 ] && { ok "All verification checks passed"; exit 0; } || die "$fails check(s) failed"
