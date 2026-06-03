# Camera Extension V2 — Plan

## Current State

Starting from scratch. The V1 implementation used the wrong Xcode product type (`extensionkit-extension`) which made the extension invisible to macOS's CMIO discovery system. All source files will be recreated.

## Architecture Overview

```
┌─────────────────────────────────┐
│  CursorFollowMac.app           │
│  (Menu bar app)                 │
│                                 │
│  ┌───────────────────────────┐  │
│  │ WindowTracker             │  │
│  │ CaptureEngine             │  │
│  │ FrameTransport (sender)   │──┼──► IOSurface / XPC ──┐
│  └───────────────────────────┘  │                       │
│                                 │                       │
│  Contents/PlugIns/              │                       │
│  ┌───────────────────────────┐  │                       │
│  │ CameraExtension.appex     │◄─┼───────────────────────┘
│  │  main.swift               │  │
│  │  CMIOExtensionProvider    │  │
│  │  CMIOExtensionDevice      │  │
│  │  CMIOExtensionStream      │  │
│  │  FrameTransport (recv)    │  │
│  └───────────────────────────┘  │
└─────────────────────────────────┘
         │
         ▼
   pluginkit discovers .appex
   via com.apple.cmio.registerassistantservice
         │
         ▼
   Conferencing apps see "CursorFollow Camera"
```

## Implementation Phases

### Phase 0: Xcode Project Setup (CRITICAL — do this first)

Goal: Create a valid Xcode project with host app + camera extension that registers with pluginkit — even if it only outputs a static color frame.

Tasks:

1. Create new Xcode project `CursorFollowMac` (macOS App, SwiftUI).
2. Add target: **Camera Extension** (File → New → Target → Camera Extension).
   - Xcode's template automatically uses `com.apple.product-type.app-extension` and generates correct `NSExtension` plist entries.
   - **Do NOT** select "ExtensionKit Extension" template.
3. Configure bundle IDs:
   - Host: `io.github.loganrupe.CursorFollowMac`
   - Extension: `io.github.loganrupe.CursorFollowMac.CameraExtension`
4. Configure signing: Team YOURTEAMID, automatic.
5. Add App Groups capability to both targets: `group.io.github.loganrupe.CursorFollowMac`.
6. Verify Info.plist has `CMIOExtension.CMIOExtensionMachServiceName` and `NSExtension.NSExtensionPointIdentifier`.
7. Build, deploy to `/Applications/`, launch.
8. **Gate: `pluginkit -mDAD -p com.apple.cmio.registerassistantservice` must show the extension.**
9. **Gate: `system_profiler SPCameraDataType` must list the camera.**

Key insight: Use Xcode's built-in "Camera Extension" template. Do NOT manually configure product types. The template gets all the subtle project settings right.

### Phase 1: Minimal Viable Camera

Goal: Output a generated test pattern (e.g., color bars or timestamp overlay) through the CMIO stream so the camera produces visible video in Photo Booth.

Tasks:

1. Implement `CMIOExtensionProviderSource` with one device and one stream.
2. Generate a test frame (solid color or simple pattern) on a timer.
3. Output 1920×1080 BGRA at 30fps via `stream.send()`.
4. Verify in Photo Booth.

Gate: Photo Booth shows the test pattern when selecting "CursorFollow Camera".

### Phase 2: Host App Capture

Goal: Host app captures a target window and makes frames available.

Tasks:

1. Implement `WindowTracker` — enumerate windows, select target.
2. Implement `CaptureEngine` — ScreenCaptureKit capture of target window.
3. Publish captured frames to shared transport (app group container or XPC).

Gate: Host app captures window content and logs frame delivery.

### Phase 3: Frame Transport (Host → Extension)

Goal: Bridge captured frames from host process to extension process.

Tasks:

1. Define IPC mechanism (IOSurface via Mach port, or shared memory via app group).
2. Implement sender in host app.
3. Implement receiver in extension.
4. Wire receiver output into CMIO stream's `send()`.

Gate: Live window content appears in Photo Booth through the virtual camera.

### Phase 4: Polish and Hardening

Goal: Production stability.

Tasks:

1. Handle target window changes gracefully (no stream interruption >300ms).
2. Handle missing permissions with clear user feedback.
3. Optimize latency to <50ms median.
4. Add menu bar UI for target selection and status.
5. Document build/install/verify flow.

Gate: 30-minute continuous test with no crashes, leaks, or frame stalls.

## File Structure (Target)

```
XcodeHost/
  CursorFollowMac/
    CursorFollowMac.xcodeproj/
    CursorFollowMac/          # Host app sources
      App.swift
      ContentView.swift
      MenuBarView.swift
      WindowTracker.swift
      CaptureEngine.swift
      Settings.swift
      Info.plist
      CursorFollowMac.entitlements
    CameraExtension/           # Extension target sources
      main.swift               # CMIOExtensionProvider.startService() + CFRunLoopRun()
      CameraProvider.swift     # CMIOExtensionProviderSource
      CameraDevice.swift       # CMIOExtensionDeviceSource
      CameraStream.swift       # CMIOExtensionStreamSource
      Info.plist               # NSExtension + CMIOExtension
      CameraExtension.entitlements
    Shared/                    # Shared between both targets
      FrameTransport.swift
      Models.swift
      SettingsStore.swift
```

## Critical "Do NOT" List

- **Do NOT** use `com.apple.product-type.extensionkit-extension` product type.
- **Do NOT** use `EXExtensionAttributes` in Info.plist.
- **Do NOT** use `com.apple.camera-extension` as extension point identifier.
- **Do NOT** use `wrapper.extensionkit-extension` file reference type.
- **Do NOT** skip the Phase 0 gate — nothing else matters if pluginkit doesn't discover the extension.
- **Do NOT** manually edit the pbxproj to set product types — use Xcode's Camera Extension template.

## Risks

1. Xcode template may not be available in Xcode 26 beta — may need to use Xcode 16.x template and migrate.
2. macOS Tahoe (26) may have changed CMIO discovery behavior — test on macOS 15 if Tahoe fails.
3. IOSurface-based transport adds complexity — start with simpler XPC frame passing if needed.
4. Code signing during development (no provisioning profile) — `get-task-allow` entitlement required for debug builds.

## Reference

- [Apple: Creating a camera extension](https://developer.apple.com/documentation/coremediaio/creating-a-camera-extension-with-core-media-i-o)
- Extension point: `com.apple.cmio.registerassistantservice`
- Product type: `com.apple.product-type.app-extension`
- Key plist keys: `CMIOExtension.CMIOExtensionMachServiceName`, `NSExtension.NSExtensionPointIdentifier`
