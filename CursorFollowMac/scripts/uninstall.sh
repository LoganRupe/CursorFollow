#!/usr/bin/env bash
#
# uninstall.sh — full uninstall cleanup for CursorFollow.
#
# macOS has no central uninstaller and no registry. Deleting the .app leaves
# preferences, caches, saved state and the TCC (Screen Recording) grant behind.
# This removes them.
#
# Usage:
#   ./scripts/uninstall.sh            # interactive, asks before removing
#   ./scripts/uninstall.sh --dry-run  # show what would be removed, change nothing
#   ./scripts/uninstall.sh --yes      # no prompt
#
# Per-user data only; no sudo needed.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

DRY=0; YES=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --yes|-y)  YES=1 ;;
    *) die "unknown flag: $a" ;;
  esac
done

run() {
  if [ "$DRY" -eq 1 ]; then echo "    would: $*"; else eval "$*"; fi
}

remove_path() {
  local p="$1"
  if [ -e "$p" ] || [ -L "$p" ]; then
    info "remove $p"
    run "rm -rf \"$p\""
  fi
}

# --- 0. Confirm -------------------------------------------------------------
if [ "$DRY" -eq 0 ] && [ "$YES" -eq 0 ]; then
  warn "This removes CursorFollow and ALL its local data for the current user."
  read -r -p "Continue? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "aborted"
fi

# --- 1. Quit the running app ------------------------------------------------
info "Stopping running app"
run "/usr/bin/pkill -x '$APP_NAME' 2>/dev/null || true"
run "/usr/bin/osascript -e 'tell application \"$APP_NAME\" to quit' 2>/dev/null || true"

# --- 2. The app bundle ------------------------------------------------------
remove_path "/Applications/$APP_NAME.app"
remove_path "$HOME/Applications/$APP_NAME.app"

# --- 3. Per-user data -------------------------------------------------------
remove_path "$HOME/Library/Preferences/$APP_BUNDLE_ID.plist"
remove_path "$HOME/Library/Containers/$APP_BUNDLE_ID"          # if ever sandboxed
remove_path "$HOME/Library/Caches/$APP_BUNDLE_ID"
remove_path "$HOME/Library/HTTPStorages/$APP_BUNDLE_ID"
remove_path "$HOME/Library/Saved Application State/$APP_BUNDLE_ID.savedState"
remove_path "$HOME/Library/Application Support/$APP_NAME"
remove_path "$HOME/Library/Logs/$APP_NAME"

# Flush the cfprefsd cache so a reinstall starts clean.
run "/usr/bin/defaults delete '$APP_BUNDLE_ID' 2>/dev/null || true"

# --- 4. Privacy (TCC) grant -------------------------------------------------
# Revoke the Screen Recording permission so a reinstall re-prompts cleanly.
info "Reset Screen Recording (TCC) grant"
run "/usr/bin/tccutil reset ScreenCapture '$APP_BUNDLE_ID' 2>/dev/null || true"

# --- 5. Login item (if the app registered one) ------------------------------
run "/usr/bin/osascript -e 'tell application \"System Events\" to delete login item \"$APP_NAME\"' 2>/dev/null || true"

echo
if [ "$DRY" -eq 1 ]; then
  ok "Dry run complete — nothing changed"
else
  ok "Uninstall cleanup complete"
fi
