# macOS Packaging, Signing & Distribution

This covers building, signing, installing, upgrading, and uninstalling
CursorFollow on macOS — the Mac equivalents of the Windows installer checklist
you started from.

> **Read this first if you copied a Windows checklist.** Most Windows packaging
> concepts do **not** map 1:1 to macOS. The table below says what translates,
> what changes, and what simply doesn't exist here.

## Windows → macOS: what's valid and what isn't

| Windows concept | macOS reality | Valid here? |
| --- | --- | --- |
| MSI / NSIS / Inno Setup installer | A **DMG** with a drag-to-`/Applications` icon. No "install wizard"; the user drags the app. (A `.pkg` is the alternative — see below.) | ✅ Reworked → `make_dmg.sh` |
| Per-machine install to `Program Files` | App lives in `/Applications` (all users) or `~/Applications`. | ✅ Different location |
| MSI upgrade codes / version comparison | Replace the `.app` bundle; macOS keys off the **bundle ID** + a higher `CFBundleShortVersionString`/`CFBundleVersion`. In-app auto-update is **Sparkle**, not built in. | ⚠️ Concept differs |
| Authenticode code-signing cert (DigiCert/EV) | **Apple Developer ID Application** cert (issued by Apple, needs the $99/yr account). Different authority entirely — you can't reuse a Windows cert. | ⚠️ Replace, don't port |
| Timestamping server | Apple's secure timestamp is automatic via `codesign`. | ✅ Automatic |
| SmartScreen reputation | **Gatekeeper + Notarization** (`notarytool`) + ticket **stapling**. This has *no* Windows analog and is mandatory for distribution. | 🆕 New step |
| Registry keys (HKLM/HKCU) | **No registry.** Settings live in `~/Library/Preferences/<bundleid>.plist` and the app-group container. | ❌ Doesn't exist |
| `Add/Remove Programs` uninstaller | **No built-in uninstaller.** Ship a script or document manual cleanup. | 🆕 → `uninstall.sh` |
| Driver / service install | N/A — the CoreMediaIO system extension was removed. (If one is ever re-added, it activates via `OSSystemExtensionRequest`, not file copies.) | ❌ Removed |
| `signtool verify` / `Get-AuthenticodeSignature` | `codesign --verify`, `spctl`, `stapler validate`. | ✅ → `verify.sh` |

**Bottom line:** the five checklist items are all valid *as goals*, but the
mechanisms are different. There's no registry cleanup, no install wizard, no
purchased signing cert, and notarization is an extra step Windows never had.

## Project facts that drive the setup

- App is **sandboxed** (`ENABLE_APP_SANDBOX = YES`) and distributed with
  **Developer ID** (notarized), not via the Mac App Store.
- **Hardened runtime is ON** (required for notarization) — already set in the project.
- No system extension and no app-group entitlement: the CoreMediaIO
  CameraExtension was removed, so the only feature is the shared-window output.
  `verify.sh`/`uninstall.sh` still check for a stray extension so they keep
  working on machines where an old build registered one.
- Identity: Team `YOURTEAMID`, app `io.github.loganrupe.CursorFollowMac`.

## One-time prerequisites

1. **Apple Developer Program** membership ($99/yr) for Team `YOURTEAMID`.
2. **Developer ID Application** certificate installed in the login keychain.
   Check with: `security find-identity -v -p codesigning` (look for
   "Developer ID Application: … (YOURTEAMID)").
3. **notarytool credentials** stored once as a keychain profile:
   ```bash
   xcrun notarytool store-credentials "CursorFollowNotary" \
     --apple-id you@example.com --team-id YOURTEAMID \
     --password <app-specific-password>
   ```
   The app-specific password comes from appleid.apple.com → Sign-In & Security,
   **not** your Apple ID password.
4. Optional, nicer DMG layout: `brew install create-dmg`.

## Code signing plan

1. Xcode signs the app with **Developer ID Application** during `archive`
   (automatic signing, hardened runtime on).
2. `-exportArchive` with `ExportOptions.plist` (`method = developer-id`)
   produces the distributable `.app`.
3. **Notarize** the `.app`, then build the DMG, then notarize the DMG, then
   **staple** tickets to both. Stapling lets Gatekeeper approve the app offline.
4. `verify.sh` confirms: valid signature, hardened-runtime flag, correct Team
   ID, Gatekeeper acceptance, and a stapled ticket — before anything ships.

## Build the installer (DMG)

Full pipeline (build → notarize → DMG → notarize → staple):

```bash
./scripts/package.sh
# → build/CursorFollowMac-<version>.dmg  (notarized, stapled, ready to ship)
```

Or step by step:

```bash
./scripts/build_release.sh      # build/export/CursorFollowMac.app (Developer ID signed)
./scripts/notarize.sh build/export/CursorFollowMac.app
./scripts/make_dmg.sh           # build/CursorFollowMac-<version>.dmg
./scripts/notarize.sh build/CursorFollowMac-<version>.dmg
./scripts/verify.sh build/CursorFollowMac-<version>.dmg
```

**DMG vs `.pkg`:** DMG is the right default here — drag-to-`/Applications` with
no install scripting to maintain. Choose a `.pkg` only if you later need an actual
installer (pre-flight scripts, choosing install location, MDM deployment). A
`.pkg` needs a separate **Developer ID Installer** certificate and
`productbuild --sign`; that path is not scripted yet.

## Upgrade path

There is no MSI-style upgrade engine. To ship an update:

1. Bump **`MARKETING_VERSION`** (user-facing) and **`CURRENT_PROJECT_VERSION`**
   (must strictly increase) in the Xcode project.
2. Run `./scripts/package.sh` to produce the new signed/notarized DMG.
3. The user drags the new app over the old one in `/Applications` (same bundle
   ID → macOS treats it as an upgrade; preferences are preserved).

**Auto-update (future):** integrate **Sparkle** (`https://sparkle-project.org`)
with a signed appcast feed. That's the standard for non-App-Store auto-updates
and replaces the Windows updater. Not wired up yet.

## Uninstall cleanup

Deleting the `.app` leaves preferences, caches, saved state, the Screen
Recording (TCC) grant, and (on machines where an old build registered one) a
stray system extension behind. Clean removal:

```bash
./scripts/uninstall.sh --dry-run   # preview exactly what would be removed
./scripts/uninstall.sh             # interactive
./scripts/uninstall.sh --yes       # unattended
```

It quits the app, removes the bundle and all per-user data, resets the Screen
Recording grant (so a reinstall re-prompts), removes any login item, and reports
whether a stray system extension is still registered. Remove that via **System
Settings → General → Login Items & Extensions → Camera Extensions** (the
`systemextensionsctl` CLI is blocked while SIP is enabled).

## Developer verification

```bash
./scripts/verify.sh build/export/CursorFollowMac.app   # or a .dmg
```

Checks signature validity (deep/strict), hardened-runtime flag, Team ID,
Gatekeeper assessment (`spctl`), and ticket
stapling. Non-zero exit on any failure — safe to gate a release on.

## Script reference (`scripts/`)

| Script | Purpose |
| --- | --- |
| `config.sh` | Shared identity/paths/helpers; sourced by the rest. Override via env. |
| `build_release.sh` | Archive + export the Developer ID signed `.app`. |
| `make_dmg.sh` | Build the drag-to-`/Applications` DMG (the installer). |
| `notarize.sh` | Submit to Apple notarization and staple the ticket (`.app`/`.dmg`/`.pkg`). |
| `package.sh` | One-shot: build → notarize → DMG → notarize → staple. |
| `verify.sh` | Verify signing, hardened runtime, Gatekeeper, notarization. |
| `uninstall.sh` | Full uninstall cleanup (app, prefs, container, TCC, login item, sysext note). |
| `ExportOptions.plist` | `xcodebuild -exportArchive` options (Developer ID). |
