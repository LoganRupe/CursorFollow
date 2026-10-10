#!/usr/bin/env bash
#
# make_signing_cert.sh — create the self-signed code-signing identity releases use.
#
# CursorFollow releases are not notarized, so they don't need an Apple Developer ID.
# They still need a *stable* signature: macOS ties the Screen Recording grant to the
# signing identity, and an ad-hoc signature changes on every build, which would make
# users re-grant the permission after each update. A self-signed cert kept in the
# login keychain gives every release the same identity.
#
# Idempotent: does nothing if the identity already exists.
#
# Usage:
#   ./scripts/make_signing_cert.sh                 # create + import into the login keychain
#   ./scripts/make_signing_cert.sh --export out.p12 # also write a backup (+ out.p12.password)
#
# Back the .p12 up somewhere safe (a password manager). Losing it means the next
# release has a new identity and every user re-grants Screen Recording once.

source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
require openssl
require security

EXPORT_P12=""
while [ $# -gt 0 ]; do
  case "$1" in
    --export) EXPORT_P12="${2:?--export needs a path}"; shift 2 ;;
    *) die "unknown flag: $1" ;;
  esac
done

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$SIGN_IDENTITY" "$KEYCHAIN" >/dev/null 2>&1; then
  ok "Signing identity \"$SIGN_IDENTITY\" already in the login keychain"
  [ -z "$EXPORT_P12" ] && exit 0
  die "--export only works when this script creates the identity; export an existing one from Keychain Access"
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

info "Generating self-signed code-signing certificate \"$SIGN_IDENTITY\" (10 years)"
cat > "$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $SIGN_IDENTITY
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem" 2>/dev/null

P12_PASS="$(openssl rand -base64 24)"
# -legacy keeps the p12 readable by `security import` when openssl 3 is on PATH.
LEGACY=""; openssl version | grep -q '^OpenSSL 3' && LEGACY="-legacy"
openssl pkcs12 -export $LEGACY -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$SIGN_IDENTITY" -passout "pass:$P12_PASS" -out "$WORK/identity.p12"

info "Importing into the login keychain (codesign allowed to use the key)"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$P12_PASS" \
  -T /usr/bin/codesign -T /usr/bin/security >/dev/null

if [ -n "$EXPORT_P12" ]; then
  ( umask 077
    cp "$WORK/identity.p12" "$EXPORT_P12"
    printf '%s\n' "$P12_PASS" > "$EXPORT_P12.password" )
  ok "Backup written to $EXPORT_P12 (import password in $EXPORT_P12.password)"
  warn "Move both into your password manager, then delete them from disk."
fi

ok "Created \"$SIGN_IDENTITY\". build_release.sh will sign with it."
