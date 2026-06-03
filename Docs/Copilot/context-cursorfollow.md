# Context: CursorFollow

## Overview

CursorFollow is a macOS menu bar utility that tracks a target window and exposes the capture as a virtual camera feed for conferencing apps.

### Product Goal

- Track the selected target window (active/focused or under cursor)
- Capture content with low latency (<50 ms target)
- Stream frames into a CoreMediaIO Camera Extension for Slack/Zoom/Meet

## Target Architecture

```
CursorFollowMac.app
├── Host app (menu bar + tracking + capture + frame sender)
└── Contents/PlugIns/CameraExtension.appex
    └── CMIO provider/device/stream (frame receiver → virtual camera)
```

## Runtime Pipeline

1. `WindowTracker` identifies the target window.
2. `CaptureEngine` captures via ScreenCaptureKit.
3. Frames sent to extension via IPC (IOSurface / XPC through app group).
4. Extension forwards frames into CMIO stream → appears as camera source.

## Key APIs

- **ScreenCaptureKit** — `SCShareableContent`, `SCContentFilter`, `SCStream`
- **CGWindowListCopyWindowInfo** — window enumeration
- **CoreMediaIO** — `CMIOExtensionProvider`, `CMIOExtensionDevice`, `CMIOExtensionStream`
- **NSWorkspace** — focused app detection

## Camera Extension — Critical Facts

- **Product type**: `com.apple.product-type.app-extension` (PlugInKit, NOT ExtensionKit)
- **Extension point**: `com.apple.cmio.registerassistantservice`
- **Info.plist**: Must have `NSExtension` dict (NOT `EXExtensionAttributes`)
- **Mach service**: `$(TeamIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`
- **Entry point**: `main.swift` → `CMIOExtensionProvider.startService()` + `CFRunLoopRun()`
- **Discovery**: Automatic when host app is in `/Applications/` and launched
- **Verification**: `pluginkit -mDAD -p com.apple.cmio.registerassistantservice`

## Implementation Notes

- Prefer stream restart on window change over stale filter updates.
- Keep queue depth low and frame interval explicit for latency control.
- Avoid capturing utility and system windows by default.
- Debounce window switches to avoid thrashing when cursor crosses dense UI.

## Permissions

- Screen Recording: mandatory for capture.
- Accessibility: improves focused-window detection reliability.

## Signing

- Team: YOURTEAMID
- Host bundle ID: `io.github.loganrupe.CursorFollowMac`
- Extension bundle ID: `io.github.loganrupe.CursorFollowMac.CameraExtension`
- App group: `group.io.github.loganrupe.CursorFollowMac`
- Both targets: sandbox enabled, hardened runtime

## Build Notes

- Must build in Xcode (not `swift build`) for extension embedding and signing.
- Use Xcode's "Camera Extension" target template — do NOT manually configure product types.
- Deploy to `/Applications/` for macOS to discover the extension.
- `swift build` can validate shared module logic but cannot prove camera visibility.
