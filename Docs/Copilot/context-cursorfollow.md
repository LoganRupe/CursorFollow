# Context: CursorFollow

## Overview

CursorFollow tracks a target window and exposes the capture through a sharing-friendly output path for conferencing and recording workflows.

- macOS currently supports a CoreMediaIO virtual camera path and a shareable output window.
- Windows should prioritize a shareable output window first, so users can keep their real camera selected in meeting apps while sharing CursorFollow's tracked-window output. Windows virtual camera work is optional/later unless explicitly requested.

### Product Goal

- Track the selected target window (active/focused or under cursor)
- Capture content with low latency (<50 ms target)
- Render frames into a shareable output window for presentation workflows
- On macOS, also stream frames into a CoreMediaIO Camera Extension for camera-source workflows

## macOS Target Architecture

```
CursorFollowMac.app
├── AppCoordinator
├── WindowTracker
├── CaptureEngine
└── OutputWindowController
    └── CursorFollow Output window
```

## Runtime Pipeline

1. `WindowTracker` identifies the target window.
2. `CaptureEngine` captures via ScreenCaptureKit.
3. Captured frames are rendered into the persistent output window.
4. User shares the output window through their conferencing app.

## Windows Target Direction

1. Window tracker identifies the active, selected, or cursor-adjacent target window.
2. Capture engine captures via Windows Graphics Capture.
3. App renders frames into a normal shareable output window that meeting apps can share as a window.
4. Optional later virtual-camera mode may publish frames through Media Foundation if the product needs camera-source behavior.

## Key APIs

- **ScreenCaptureKit** — `SCShareableContent`, `SCContentFilter`, `SCStream`
- **CGWindowListCopyWindowInfo** — window enumeration
- **AppKit / SwiftUI** — output window lifecycle and controls
- **Metal or Core Animation** — low-latency frame presentation
- **NSWorkspace** — focused app detection

## Active Plan

- Current product plan: `Docs/SharedWindowV1/index.html`.
- Requirements: `Docs/SharedWindowV1/requirements.html`.
- Implementation plan: `Docs/SharedWindowV1/plan.html`.
- Recommended branch: `feature/shared-window-output`.

## Camera Extension Notes

`Docs/CameraExtensionV2/` remains as historical reference for the virtual camera path. Do not default new work toward CoreMediaIO unless the product direction changes again.

## Implementation Notes

- Keep the output window identity stable across target switches so meeting apps do not lose the shared source.
- Exclude CursorFollow's own control and output windows from target candidates.
- Keep queue depth low; render the latest frame rather than accumulating stale frames.
- Avoid capturing utility and system windows by default.
- Avoid capturing CursorFollow's own output window by default to prevent feedback loops.
- Debounce window switches to avoid thrashing when cursor crosses dense UI.

## Permissions

- Screen Recording: mandatory for capture.
- Accessibility: not part of the current Shared Window V1 permission flow unless a future implementation adds AX APIs.
- Camera permission: not required for Shared Window V1.

## Signing

- Team: YOURTEAMID
- Host bundle ID: `io.github.loganrupe.CursorFollowMac`
- Shared Window V1 should not require CoreMediaIO extension signing, PlugInKit discovery, or camera entitlements.

## Build Notes

- Build with Xcode for macOS app validation.
- Validate the output window in conferencing screen-share pickers early.
- Keep the output window visible and non-minimized during picker validation.
