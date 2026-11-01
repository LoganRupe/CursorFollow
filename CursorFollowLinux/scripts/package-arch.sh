#!/usr/bin/env bash
#
# package-arch.sh — build the Arch package from this checkout, not the tag tarball.
#
# Packs HEAD into the tarball name the PKGBUILD expects and runs makepkg with checksums
# skipped (the PKGBUILD pins the published tag's hash, which HEAD won't match), so a
# packaging break shows up on the PR that caused it. Produces, in build/arch/:
#   cursorfollow-<ver>-<rel>-<arch>.pkg.tar.zst
#   cursorfollow-<ver>-<arch>.tar.gz   (the install tree, usr/...)
#
# Run as a non-root user on Arch with base-devel. Extra args go to makepkg (e.g. -s).
# Usage: ./CursorFollowLinux/scripts/package-arch.sh [makepkg args...]

set -euo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
OUT="$ROOT/CursorFollowLinux/build/arch"

rm -rf "$OUT"
mkdir -p "$OUT"
cp "$ROOT/CursorFollowLinux/packaging/arch/PKGBUILD" "$OUT/"
cd "$OUT"

eval "$(makepkg --printsrcinfo | awk -F' = ' '/^\tpkgver/ {print "VER=" $2} /^pkgname/ {print "NAME=" $2}')"
ARCH="$(uname -m)"

git -C "$ROOT" archive --prefix="CursorFollow-$VER/" -o "$OUT/$NAME-$VER.tar.gz" HEAD
makepkg -f --skipchecksums --noconfirm "$@"

PKG="$(ls "$NAME-$VER"-*-"$ARCH".pkg.tar.zst)"
mkdir tree
bsdtar -xf "$PKG" -C tree --exclude '.*'
tar -czf "$NAME-$VER-$ARCH.tar.gz" -C tree usr

echo "Built $OUT/$PKG"
echo "Built $OUT/$NAME-$VER-$ARCH.tar.gz"
