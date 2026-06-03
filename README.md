# CursorFollow (macOS)

A macOS menu bar utility that captures an app window and publishes it as a virtual camera feed via a CoreMediaIO camera extension. Use it in Zoom, Slack, Google Meet, OBS, and other camera-enabled apps.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Screenshots](#screenshots)
- [Permissions](#permissions)
- [Troubleshooting](#troubleshooting)
    - [Reset Checklist](#reset-checklist-when-things-are-stuck)
- [Developer Documentation](#developer-documentation)
    - [Architecture](#architecture)
    - [Build & Deploy](#build--deploy)
    - [Signing](#signing)
    - [Project Structure](#project-structure)

## Overview

CursorFollow runs in your menu bar and publishes a virtual camera named **CursorFollow Camera**. It can follow your active window automatically, or let you lock to a specific window manually.

## Quick Start

1. Launch `CursorFollowHost.app`.
2. When prompted, allow:
   - **Screen Recording** (required for window capture)
   - **System Extension** approval in System Settings
3. Open the CursorFollow menu bar panel.
4. Pick a target window from the list (or keep **Auto-follow cursor** enabled).
5. Click **Start**.
6. In your video app, select **CursorFollow Camera** as your camera source.

## Usage

- **Auto-follow cursor**: Automatically tracks the app/window you are actively using.
- **Filter mode**: Use **All / Exclude / Include** to control which windows appear as capture targets.
- **Refresh**: Re-scan active windows if the list looks stale or incomplete.
- **Show**: Bring the output preview window to the front.
- **Start / Stop**: Start or stop virtual camera output.

## Screenshots

### Menu bar panel

![CursorFollow menu bar panel](Docs/images/readme/main-panel.png)

### Settings window

![CursorFollow settings window](Docs/images/readme/settings-window.png)

## Permissions

- **Screen Recording**: Required for ScreenCaptureKit window capture.
- **System Extension**: Approve in System Settings → Privacy & Security when prompted.

## Troubleshooting

### Reset checklist (when things are stuck)

1. Quit your video app (Zoom/Meet/Slack/OBS) and quit CursorFollow.
2. In **System Settings → Privacy & Security → Screen Recording**, verify CursorFollow is enabled.
3. In **System Settings → Privacy & Security**, confirm the system extension is approved.
4. Reopen CursorFollow, click **Refresh**, select the target window, then click **Start**.
5. Reopen your video app and reselect **CursorFollow Camera** as the camera source.

### Permission paths by macOS version

- **macOS 13 Ventura / 14 Sonoma / 15 Sequoia**
    - Screen capture access: **System Settings → Privacy & Security → Screen Recording**
    - System extension approval: **System Settings → Privacy & Security** (look for the allow prompt near the bottom after first launch)

### CursorFollow Camera does not appear in Zoom/Meet/Slack

- Ensure CursorFollow is running and capture is started.
- Confirm **System Extension** approval in System Settings → Privacy & Security.
- Quit and reopen the video app after first-time extension approval.
- In the video app's camera selector, choose **CursorFollow Camera** explicitly (some apps stay on the previous camera device).

### Output is black or frozen

- Confirm **Screen Recording** permission is enabled for CursorFollow in System Settings → Privacy & Security → Screen Recording.
- Click **Refresh**, then reselect the target window.
- Stop and restart capture from the menu bar panel.

### Wrong window is being captured

- Disable **Auto-follow cursor** and manually select a specific window.
- Use **Include** mode to limit capture targets to approved windows.

### Capture feels choppy or high CPU

- In Settings, switch capture quality from **Balanced** to **Performant** or **Low-Latency**.
- Reduce competing screen capture/recording tools running at the same time.
- If needed, capture a smaller target window instead of a full-size display window.

## Developer Documentation

### Features

- **Auto-follow**: Automatically switches capture target when you change apps (toggleable)
- **Manual selection**: Pick any window from the list for manual capture
- **Virtual camera**: Captured frames appear as "CursorFollow Camera" in any video app
- **Low latency**: Direct IOSurface sharing between host and extension, no file I/O
- **60fps capture**: 1920×1080 BGRA at 60fps via ScreenCaptureKit

### Architecture

```
CursorFollowHost.app (menu bar)
├── WindowTracker — monitors frontmost app, enumerates windows
├── CaptureEngine — SCStream capture → IOSurface
├── FrameTransport — shared IOSurface + Darwin notify signaling
└── CameraExtension (system extension)
    └── CMIO provider → reads IOSurface → outputs as virtual camera
```

### Build & Deploy

**Important:** Xcode incremental builds and macOS binary caching can cause stale code to run. Always follow this sequence.

```bash
cd ~/repos/CursorFollow-mac/CursorFollowHost

# 1. Kill any running instance (MUST do first — old process keeps stale dylib in memory)
pkill -9 -f CursorFollowHost 2>/dev/null; sleep 1

# 2. Clean build (forces full recompilation — avoids stale object files)
xcodebuild -scheme CursorFollowHost -configuration Debug clean build

# 3. Remove old app bundle
rm -rf /Applications/CursorFollowHost.app

# 4. Deploy fresh build
cp -R ~/Library/Developer/Xcode/DerivedData/CursorFollowHost-cfwezmilauwvqiahnvdrwzhgozpu/Build/Products/Debug/CursorFollowHost.app /Applications/CursorFollowHost.app

# 5. Verify new binary (UUID should differ from previous deploy)
dwarfdump --uuid /Applications/CursorFollowHost.app/Contents/MacOS/CursorFollowHost.debug.dylib

# 6. Launch
open /Applications/CursorFollowHost.app
```

**One-liner:**
```bash
pkill -9 -f CursorFollowHost 2>/dev/null; sleep 1 && cd ~/repos/CursorFollow-mac/CursorFollowHost && xcodebuild -scheme CursorFollowHost -configuration Debug clean build && rm -rf /Applications/CursorFollowHost.app && cp -R ~/Library/Developer/Xcode/DerivedData/CursorFollowHost-cfwezmilauwvqiahnvdrwzhgozpu/Build/Products/Debug/CursorFollowHost.app /Applications/CursorFollowHost.app && open /Applications/CursorFollowHost.app
```

**If the DerivedData hash changes** (after clean clone, Xcode update, etc.):
```bash
ls ~/Library/Developer/Xcode/DerivedData/ | grep CursorFollow
```
Then update the path in the commands above.

**Why each step matters:**

| Step | Prevents |
|------|----------|
| `pkill -9` first | macOS keeps old dylib mapped in memory; `cp` appears to succeed but process uses old code |
| `clean build` | Incremental builds skip recompiling files Xcode incorrectly thinks haven't changed |
| `rm -rf` before `cp` | `cp -R` over existing bundle can leave stale nested files behind |
| `dwarfdump --uuid` | Proves the on-disk binary is actually new |

### Signing

- Team ID: `YOURTEAMID`
- App Group: `group.io.github.loganrupe.CursorFollowHost`
- Host Bundle: `io.github.loganrupe.CursorFollowHost`
- Extension Bundle: `io.github.loganrupe.CursorFollowHost.CameraExtension`

### Project Structure

```
CursorFollowHost/
├── CursorFollowHost/          # Host app sources
│   ├── CursorFollowHostApp.swift   # App entry + AppCoordinator
│   ├── ContentView.swift           # Menu bar panel UI
│   ├── WindowTracker.swift         # Window enumeration + auto-follow
│   ├── CaptureEngine.swift         # ScreenCaptureKit capture
│   └── FrameTransport.swift        # IOSurface shared memory transport
├── CameraExtension/           # CoreMediaIO system extension
│   ├── CameraExtensionProvider.swift  # CMIO device/stream + frame receiver
│   ├── main.swift                     # Extension entry point
│   └── Info.plist                     # Extension point config
└── CursorFollowHost.xcodeproj/
```
