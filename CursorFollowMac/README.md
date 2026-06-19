# CursorFollowMac

macOS host app for CursorFollow's shared-window workflow. The historical CameraExtension target remains in the project, but Shared Window V1 renders into the host-owned `CursorFollow Output` window.

## Quick Build

From the repository root:

```bash
cd CursorFollowMac
xcodebuild -project CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates clean build
```

Or from anywhere:

```bash
xcodebuild -project ~/repos/CursorFollow/CursorFollowMac/CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates clean build
```

## Build & Deploy (Stale-Binary Safe)

Xcode incremental builds and macOS binary caching can run stale code. Use this sequence when validating runtime changes.

```bash
cd ~/repos/CursorFollow/CursorFollowMac

# 1. Kill any running instance first.
pkill -9 -f CursorFollowMac 2>/dev/null; sleep 1

# 2. Force a clean build.
xcodebuild -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates clean build

# 3. Replace existing app bundle.
rm -rf /Applications/CursorFollowMac.app
cp -R ~/Library/Developer/Xcode/DerivedData/CursorFollowMac-*/Build/Products/Debug/CursorFollowMac.app /Applications/CursorFollowMac.app

# 4. Optional: verify binary UUID changed.
dwarfdump --uuid /Applications/CursorFollowMac.app/Contents/MacOS/CursorFollowMac.debug.dylib

# 5. Launch.
open /Applications/CursorFollowMac.app
```

One-liner:

```bash
pkill -9 -f CursorFollowMac 2>/dev/null; sleep 1 && cd ~/repos/CursorFollow/CursorFollowMac && xcodebuild -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates clean build && rm -rf /Applications/CursorFollowMac.app && cp -R ~/Library/Developer/Xcode/DerivedData/CursorFollowMac-*/Build/Products/Debug/CursorFollowMac.app /Applications/CursorFollowMac.app && open /Applications/CursorFollowMac.app
```

If this is the first signed build on a machine, run once from a logged-in Xcode session so account credentials are available for profile creation.

## Signing Identifiers

- Team ID: `YOURTEAMID`
- Host Bundle: `io.github.loganrupe.CursorFollowMac`

The app is sandboxed (no system-extension or app-group entitlements). The
CoreMediaIO virtual-camera extension was removed — the shipping feature is the
shared-window output, not a virtual camera.

## Project Structure

```text
CursorFollowMac/
├── CursorFollowMac/               # Host app sources
├── CursorFollowMacTests/
├── CursorFollowMacUITests/
├── scripts/                       # Packaging/signing/notarization tooling
└── CursorFollowMac.xcodeproj/
```

## Packaging & Distribution

Build, sign, notarize, install, and uninstall scripts live in [scripts/](scripts/).
Run them from the repo root, e.g. `./CursorFollowMac/scripts/package.sh`. See
[Docs/Distribution/Packaging.md](../Docs/Distribution/Packaging.md) for the full
workflow and the Windows→macOS mapping.
