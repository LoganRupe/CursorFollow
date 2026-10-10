# macOS Packaging, Signing & Distribution

How CursorFollow for macOS is built, signed, packaged, upgraded and uninstalled.
The Windows installer is covered in [CursorFollowWin/docs/Installer.md](../../CursorFollowWin/docs/Installer.md).

## Project facts that drive the setup

- App is **sandboxed** (`ENABLE_APP_SANDBOX = YES`) with the **hardened runtime** on.
- Releases are signed with a **self-signed certificate** and are **not notarized**.
  There is no Apple Developer account involved. Gatekeeper blocks the first launch,
  and the user approves it once in **System Settings → Privacy & Security → Open
  Anyway** (steps in [CursorFollowMac/README.md](../../CursorFollowMac/README.md#install)).
- The certificate exists to keep the signature identical between releases. macOS
  ties the Screen Recording grant to the signing identity; an ad-hoc signature
  changes every build, so users would have to re-grant the permission after
  every update.
- Bundle ID: `io.github.loganrupe.CursorFollowMac`.

## One-time prerequisites

1. Create the signing identity in your login keychain and keep a backup:
   ```bash
   ./CursorFollowMac/scripts/make_signing_cert.sh --export ~/CursorFollowSelfSigned.p12
   ```
   Store the `.p12` and its `.p12.password` file in a password manager, then
   delete them from disk. Losing the certificate means the next release gets a
   new identity and every user re-grants Screen Recording once.
2. The first `codesign` run shows a keychain prompt for the key. Enter your login
   password and choose **Always Allow**.
3. Optional, nicer DMG layout: `brew install create-dmg`.

To restore the identity on a new build machine, double-click the `.p12` (or
`security import CursorFollowSelfSigned.p12 -k ~/Library/Keychains/login.keychain-db -T /usr/bin/codesign`).

## Build the installer (DMG)

Full pipeline (build → sign → DMG → verify):

```bash
./CursorFollowMac/scripts/package.sh
# → build/CursorFollowMac-<version>.dmg
```

Or step by step:

```bash
./CursorFollowMac/scripts/build_release.sh      # build/export/CursorFollowMac.app (self-signed)
./CursorFollowMac/scripts/make_dmg.sh           # build/CursorFollowMac-<version>.dmg
./CursorFollowMac/scripts/verify.sh build/CursorFollowMac-<version>.dmg
```

`build_release.sh` lets Xcode build with an ad-hoc signature, then re-signs the
app with `SIGN_IDENTITY` (default `CursorFollow Self-Signed`) and the entitlements
Xcode generated. `SIGN_IDENTITY=- ./CursorFollowMac/scripts/package.sh` produces an
ad-hoc signed build if you don't have the certificate.

## Upgrade path

There is no MSI-style upgrade engine. To ship an update:

1. Bump **`MARKETING_VERSION`** (user-facing) and **`CURRENT_PROJECT_VERSION`**
   (must strictly increase) in the Xcode project.
2. Run `./CursorFollowMac/scripts/package.sh` to produce the new DMG, signed with the same certificate.
3. The user drags the new app over the old one in `/Applications` (same bundle
   ID → macOS treats it as an upgrade; preferences are preserved).

**Auto-update (future):** integrate **Sparkle** (`https://sparkle-project.org`)
with a signed appcast feed. That's the standard for non-App-Store auto-updates
and replaces the Windows updater. Not wired up yet.

## Uninstall cleanup

Deleting the `.app` leaves preferences, caches, saved state and the Screen
Recording (TCC) grant behind. Clean removal:

```bash
./CursorFollowMac/scripts/uninstall.sh --dry-run   # preview exactly what would be removed
./CursorFollowMac/scripts/uninstall.sh             # interactive
./CursorFollowMac/scripts/uninstall.sh --yes       # unattended
```

It quits the app, removes the bundle and all per-user data, resets the Screen
Recording grant (so a reinstall re-prompts) and removes any login item.

## Developer verification

```bash
./CursorFollowMac/scripts/verify.sh build/export/CursorFollowMac.app   # or a .dmg
```

Checks signature validity (deep/strict), bundle ID, signing identity, the
hardened-runtime flag and the App Sandbox entitlement. It skips Gatekeeper
(`spctl`), which rejects un-notarized builds by design. Non-zero exit on any
failure, so it is safe to gate a release on.

## Script reference (`CursorFollowMac/scripts/`)

| Script | Purpose |
| --- | --- |
| `config.sh` | Shared identity/paths/helpers; sourced by the rest. Override via env. |
| `make_signing_cert.sh` | Create the self-signed release identity (idempotent), optionally export a backup. |
| `build_release.sh` | Build the Release `.app` and sign it with the release identity. |
| `make_dmg.sh` | Build the drag-to-`/Applications` DMG (the installer). |
| `package.sh` | One-shot: build → sign → DMG → verify. |
| `verify.sh` | Verify signature, identity, hardened runtime and sandbox. |
| `uninstall.sh` | Full uninstall cleanup (app, prefs, caches, TCC grant, login item). |
