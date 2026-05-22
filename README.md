# CursorFollow (macOS)

A macOS menu bar utility that automatically tracks the frontmost window and exposes it as a virtual camera feed via a CoreMediaIO camera extension — usable in Zoom, Slack, Meet, OBS, etc.

## Features

- **Auto-follow**: Automatically switches capture target when you change apps (toggleable)
- **Manual selection**: Pick any window from the list for manual capture
- **Virtual camera**: Captured frames appear as "CursorFollow Camera" in any video app
- **Low latency**: Direct IOSurface sharing between host and extension, no file I/O
- **60fps capture**: 1920×1080 BGRA at 60fps via ScreenCaptureKit

## Architecture

```
CursorFollowHost.app (menu bar)
├── WindowTracker — monitors frontmost app, enumerates windows
├── CaptureEngine — SCStream capture → IOSurface
├── FrameTransport — shared IOSurface + Darwin notify signaling
└── CameraExtension (system extension)
    └── CMIO provider → reads IOSurface → outputs as virtual camera
```

## Build & Deploy

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

## Runtime Permissions

- **Screen Recording**: Required for ScreenCaptureKit window capture
- **System Extension**: Approve in System Settings → Privacy & Security when prompted

## Signing

- Team ID: `YOURTEAMID`
- App Group: `group.io.github.loganrupe.CursorFollowHost`
- Host Bundle: `io.github.loganrupe.CursorFollowHost`
- Extension Bundle: `io.github.loganrupe.CursorFollowHost.CameraExtension`

## Project Structure

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
