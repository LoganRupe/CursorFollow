#!/usr/bin/env bash
# Shared configuration + helpers for CursorFollow macOS packaging scripts.
# Source this from other scripts: `source "$(dirname "$0")/config.sh"`
#
# Override any value via the environment, e.g.:
#   SIGN_IDENTITY="My Cert" ./scripts/package.sh

set -euo pipefail

# --- Identity ---------------------------------------------------------------
APP_NAME="${APP_NAME:-CursorFollowMac}"
SCHEME="${SCHEME:-CursorFollowMac}"

APP_BUNDLE_ID="${APP_BUNDLE_ID:-io.github.loganrupe.CursorFollowMac}"

# Self-signed code-signing identity created by make_signing_cert.sh. Releases are
# not notarized; the cert only keeps the signature stable between versions so the
# Screen Recording grant survives updates. Set to "-" for an ad-hoc signature.
SIGN_IDENTITY="${SIGN_IDENTITY:-CursorFollow Self-Signed}"

# --- Paths ------------------------------------------------------------------
# Scripts live in CursorFollowMac/scripts/, so the project dir is one level up
# and the repo root is two.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT="$PROJECT_DIR/CursorFollowMac.xcodeproj"
BUILD_DIR="${BUILD_DIR:-$REPO_ROOT/build}"
DERIVED_DATA="$BUILD_DIR/DerivedData"
EXPORT_DIR="$BUILD_DIR/export"
APP_PATH="$EXPORT_DIR/$APP_NAME.app"

# --- Pretty output ----------------------------------------------------------
_c() { printf '\033[%sm%s\033[0m\n' "$1" "$2"; }
info()  { _c "1;34" "==> $*"; }
ok()    { _c "1;32" "ok  $*"; }
warn()  { _c "1;33" "!!  $*" >&2; }
die()   { _c "1;31" "xx  $*" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
