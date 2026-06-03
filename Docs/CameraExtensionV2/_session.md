# Session: CameraExtensionV2

## Metadata

- Date: 2026-05-20
- Branch: `main` (fresh project — no branch ceremony needed)
- Owner: unassigned
- Status: In Progress

## Goal

Rebuild the CursorFollow camera extension from scratch as a correctly-typed **PlugInKit app extension** that macOS actually discovers and registers as a virtual camera source.

## Scope

- In scope:
  - Clean Xcode project with properly configured camera extension target.
  - Correct product type, extension point, and Info.plist configuration.
  - Verified pluginkit registration and camera device enumeration.
  - Host-to-extension frame transport via XPC/IOSurface.
  - Signing, entitlements, and deployment documentation.
- Out of scope:
  - Advanced capture modes, visual effects, transitions.
  - iOS/visionOS support.

## Constraints

- macOS runtime target: 14+ (development machine: macOS 26 Tahoe).
- Extension must register with `pluginkit -mDAD -p com.apple.cmio.registerassistantservice`.
- Performance target: <50 ms median capture-to-output latency.
- Team ID: YOURTEAMID
- Bundle ID prefix: io.github.loganrupe.CursorFollowMac

## Progress Checklist

- [x] Requirements documented
- [x] Plan documented
- [x] Xcode project created with correct target types (system extension via template)
- [x] Extension registers (`systemextensionsctl list` → activated enabled)
- [x] Camera visible in `system_profiler SPCameraDataType` ("CursorFollow Camera")
- [x] WindowTracker enumerates on-screen windows (23 windows found)
- [x] CaptureEngine captures target window at 60fps via ScreenCaptureKit
- [x] FrameTransport publishes frames to shared IOSurface in app group container
- [x] Frame delivery logged (2400+ frames delivered in test)
- [x] **Phase 2 gate passed**: Host app captures window content and logs frame delivery
- [x] Frame receiver implemented in extension (IOSurfaceLookup + metadata polling)
- [x] Frame transport working host → extension (Phase 3) — IOSurface + Darwin notify
- [x] Live window content visible in Photo Booth via virtual camera (Phase 3)
- [x] Auto-follow frontmost app (auto-switch capture target on app activation)
- [x] AppCoordinator pattern for view-independent lifecycle
- [x] Threading crash fix (CaptureStreamOutput closure isolation)
- [x] Docs updated after full implementation

## Decisions

- **2026-05-20**: Working directly on `main` — this is a greenfield project, not a feature on an existing codebase. No branch overhead.
- **2026-05-20**: Phase 2 transport uses IOSurface in app group container (`group.io.github.loganrupe.CursorFollowMac`) with a 28-byte metadata signaling file. IOSurface ID is written to metadata so extension can look it up in Phase 3.
- **2026-05-20**: CaptureEngine owns the FrameTransport (simpler than cross-object wiring via notifications).
- **2026-05-22**: Replaced metadata file signaling with Darwin notifications (`notify_set_state` + `notify_post`) for cross-process surface ID sharing. Removed all file-based metadata.
- **2026-05-22**: Refactored CaptureStreamOutput to use `@Sendable` closures capturing `frameTransport` directly — eliminates actor-isolation crash from background capture queue.
- **2026-05-22**: Introduced `AppCoordinator` to own WindowTracker + CaptureEngine and wire Combine subscriptions at init. Fixes auto-follow not working until menu bar panel was opened.

## Phase 2 Implementation Notes

### Files Added
- `CursorFollowMac/WindowTracker.swift` — SCShareableContent-based window enumeration with filtering
- `CursorFollowMac/CaptureEngine.swift` — SCStream capture at 1920×1080@60fps BGRA
- `CursorFollowMac/FrameTransport.swift` — IOSurface shared memory + metadata file transport
- `CursorFollowMac/ContentView.swift` — Window picker UI with capture controls
- `CursorFollowMac/CursorFollowMacApp.swift` — Wires WindowTracker + CaptureEngine as environment objects

### Architecture
```
WindowTracker (enumerates windows)
       │ user selects
       ▼
CaptureEngine (SCStream → CMSampleBuffer)
       │ publishes
       ▼
SharedMemoryFrameTransport
       │ writes to
       ├─ IOSurface (frame pixels, 1920×1080 BGRA)
       └─ frame_metadata.bin (sequence + timestamp + surfaceID)
              in ~/Library/Group Containers/group.io.github.loganrupe.CursorFollowMac/
```

### Edge Cases Noted
- Minimized windows: SCShareableContent excludes them (onScreenWindowsOnly: true)
- Full-screen apps: Captured normally via desktopIndependentWindow filter
- Window disappears: WindowTracker clears selection on refresh; CaptureEngine stops
- Permission denied: UI shows guidance to grant Screen Recording in System Settings
- Target switch: stopCapture → startCapture with new filter (<300ms target)

## Phase 3 Implementation Notes

### Changes Made
- `CameraExtension/CameraExtensionProvider.swift` — Replaced test-pattern timer with IOSurface frame receiver

### Architecture (Extension Side)
```
Timer fires at 60fps
       │
       ▼
readFrameMetadata(from: frame_metadata.bin)
       │ compare sequence number
       ▼
IOSurfaceLookup(surfaceID) — cached, re-acquired on ID change
       │
       ▼
copySurface(into: CVPixelBuffer) — lock(readOnly), memcpy rows, unlock
       │
       ▼
stream.send(sampleBuffer)
```

### Design Decisions
- **Polling at frame rate**: Timer fires at 60fps and checks sequence number. If no new frame, repeats last frame (avoids black flicker during brief stalls).
- **Fallback to black**: If metadata file is missing or IOSurfaceLookup fails, outputs black frames (graceful degradation).
- **Minimal lock duration**: IOSurface locked only during the row-copy loop, then immediately unlocked.
- **Surface caching**: IOSurfaceLookup only called when surfaceID changes (avoids repeated Mach port lookups).
- **No buffering/queue**: Single-frame transport — always shows latest frame, never accumulates latency.
