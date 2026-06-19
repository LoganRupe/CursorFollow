# CursorFollowMac

macOS host app for CursorFollow's shared-window workflow. CursorFollow runs in the menu bar and renders a target window into a stable, shareable window named **CursorFollow Output**. The historical CameraExtension target remains in the project, but Shared Window V1 renders into the host-owned `CursorFollow Output` window — the shipping feature is the shared window, not a virtual camera.

> New here? See the [project overview](../README.md) for what CursorFollow does and the controls that are common to macOS and Windows.

## Table of Contents

- [Quick Start](#quick-start)
- [Permissions](#permissions)
- [Screenshots](#screenshots)
- [Troubleshooting](#troubleshooting)
    - [Reset checklist](#reset-checklist-when-things-are-stuck)
- [Building & Developing](#building--developing)

---

## Quick Start

1. Launch `CursorFollowMac.app`.
2. When prompted, allow **Screen Recording** (required for window capture).
3. Open the CursorFollow menu bar panel.
4. Pick a target window from the list, or set **Target Mode** to **Auto**.
5. Click **Resume** if output is paused.
6. In your meeting app, share the window named **CursorFollow Output**.

See [How It Works](../README.md#how-it-works) for what Target Mode, Filter mode, Output scaling, and Resume/Pause do.

## Permissions

- **Screen Recording**: Required for ScreenCaptureKit window capture.
    - **macOS 13 Ventura / 14 Sonoma / 15 Sequoia**: **System Settings → Privacy & Security → Screen Recording**.

The app is sandboxed (no system-extension or app-group entitlements).

## Screenshots

### Menu bar panel

![CursorFollow menu bar panel](../Docs/images/readme/main-panel.png)

### Settings window

![CursorFollow settings window](../Docs/images/readme/settings-window.png)

## Troubleshooting

### Reset checklist (when things are stuck)

1. Quit your video app (Zoom/Meet/Slack/OBS) and quit CursorFollow.
2. In **System Settings → Privacy & Security → Screen Recording**, verify CursorFollow is enabled.
3. Reopen CursorFollow, click **Refresh**, select the target window, then click **Resume**.
4. Reopen your meeting app and reselect **CursorFollow Output** as the shared window.

### CursorFollow Output does not appear in Zoom/Meet/Slack/Teams

- Ensure CursorFollow is running and **CursorFollow Output** is visible.
- Use the meeting app's **Share Screen** or **Share Window** picker, not the camera selector.
- If the picker was already open, close and reopen it after showing the output window.

### Output is black or frozen

- Confirm **Screen Recording** permission is enabled for CursorFollow in System Settings → Privacy & Security → Screen Recording.
- Click **Refresh**, then reselect the target window.
- Pause and resume output from the menu bar panel.

### Wrong window is being captured

- Set **Target Mode** to **Manual** and select a specific window.
- Use **Include** mode to limit capture targets to approved windows.

### Capture feels choppy or high CPU

- In Settings, switch capture quality from **Balanced** to **Performant** or **Low-Latency**.
- Reduce competing screen capture/recording tools running at the same time.
- If needed, capture a smaller target window instead of a full-size display window.

---

## Building & Developing

### Quick Build

From the repository root:

```bash
cd CursorFollowMac
xcodebuild -project CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates clean build
```

Or from anywhere:

```bash
xcodebuild -project ~/repos/CursorFollow/CursorFollowMac/CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -allowProvisioningUpdates clean build
```

### Build & Deploy (Stale-Binary Safe)

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

### Signing Identifiers

- Team ID: `YOURTEAMID`
- Host Bundle: `io.github.loganrupe.CursorFollowMac`

The app is sandboxed (no system-extension or app-group entitlements). The
CoreMediaIO virtual-camera extension was removed — the shipping feature is the
shared-window output, not a virtual camera.

### Project Structure

```text
CursorFollowMac/
├── CursorFollowMac/               # Host app sources
├── CursorFollowMacTests/
├── CursorFollowMacUITests/
├── scripts/                       # Packaging/signing/notarization tooling
└── CursorFollowMac.xcodeproj/
```

### Packaging & Distribution

Build, sign, notarize, install, and uninstall scripts live in [scripts/](scripts/).
Run them from the repo root, e.g. `./CursorFollowMac/scripts/package.sh`. See
[Docs/Distribution/Packaging.md](../Docs/Distribution/Packaging.md) for the full
workflow and the Windows→macOS mapping.
