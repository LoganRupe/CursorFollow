#!/usr/bin/env bash
# Shared configuration + helpers for CursorFollow macOS packaging scripts.
# Source this from other scripts: `source "$(dirname "$0")/config.sh"`
#
# Override any value via the environment, e.g.:
#   NOTARY_PROFILE=my-profile ./scripts/package.sh

set -euo pipefail

# --- Identity ---------------------------------------------------------------
TEAM_ID="${TEAM_ID:-YOURTEAMID}"
APP_NAME="${APP_NAME:-CursorFollowMac}"
SCHEME="${SCHEME:-CursorFollowMac}"

APP_BUNDLE_ID="${APP_BUNDLE_ID:-io.github.loganrupe.CursorFollowMac}"

# Legacy: the CameraExtension + app group were removed from the project. These
# remain only so uninstall.sh can clean up machines where an old build left them.
EXT_BUNDLE_ID="${EXT_BUNDLE_ID:-io.github.loganrupe.CursorFollowMac.CameraExtension}"
APP_GROUP="${APP_GROUP:-group.io.github.loganrupe.CursorFollowMac}"

# Developer ID Application identity used to sign for distribution-outside-the-App-Store.
# Run `security find-identity -v -p codesigning` to see what is installed.
SIGN_IDENTITY="${SIGN_IDENTITY:-Developer ID Application: ($TEAM_ID)}"

# notarytool keychain profile created once with:
#   xcrun notarytool store-credentials "$NOTARY_PROFILE" \
#     --apple-id you@example.com --team-id YOURTEAMID --password <app-specific-pw>
NOTARY_PROFILE="${NOTARY_PROFILE:-CursorFollowNotary}"

# --- Paths ------------------------------------------------------------------
# Scripts live in CursorFollowMac/scripts/, so the project dir is one level up
# and the repo root is two.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT="$PROJECT_DIR/CursorFollowMac.xcodeproj"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

# --- Pretty output ----------------------------------------------------------
_c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
info()  { _c "1;34" "==> $*"; }
ok()    { _c "1;32" "ok  $*"; }
warn()  { _c "1;33" "!!  $*" >&2; }
die()   { _c "1;31" "xx  $*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
