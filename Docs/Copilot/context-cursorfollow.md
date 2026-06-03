# Context: CursorFollow

## Overview

CursorFollow is a macOS menu bar utility that tracks a target window and presents the capture in a stable output window that users can share from conferencing apps.

### Product Goal

- Track the selected target window (active/focused or under cursor).
- Capture content with low latency (<50 ms target).
- Render frames into a persistent macOS window named like `CursorFollow Output`.
- Let users choose that output window from Zoom/Meet/Slack/Teams screen-share pickers.

## Target Architecture

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
- Debounce window switches to avoid thrashing when cursor crosses dense UI.

## Permissions

- Screen Recording: mandatory for capture.
- Accessibility: improves focused-window detection reliability.
- Camera permission: not required for Shared Window V1.

## Signing

- Team: YOURTEAMID
- Host bundle ID: `io.github.loganrupe.CursorFollowMac`
- Shared Window V1 should not require CoreMediaIO extension signing, PlugInKit discovery, or camera entitlements.

## Build Notes

- Build with Xcode for macOS app validation.
- Validate the output window in conferencing screen-share pickers early.
- Keep the output window visible and non-minimized during picker validation.
