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

## Build & Run

```bash
# Build via Xcode
cd CursorFollowHost
xcodebuild -scheme CursorFollowHost -configuration Debug build

# Deploy
cp -R ~/Library/Developer/Xcode/DerivedData/CursorFollowHost-*/Build/Products/Debug/CursorFollowHost.app /Applications/
open /Applications/CursorFollowHost.app
```

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
