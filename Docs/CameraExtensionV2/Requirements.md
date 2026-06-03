# Camera Extension V2 — Requirements

## Objective

Make CursorFollow appear as a selectable virtual camera in conferencing apps by implementing a **correctly-typed CoreMediaIO camera extension** that macOS discovers through PlugInKit.

## Why V2?

The V1 attempt used `com.apple.product-type.extensionkit-extension` (ExtensionKit) with the `com.apple.camera-extension` extension point. This configuration **does not work** — macOS's CMIO daemon discovers camera extensions exclusively through PlugInKit using the `com.apple.cmio.registerassistantservice` extension point. The extension compiled and deployed but was completely invisible to pluginkit, system_profiler, and all camera clients.

## What We Know (From V1 Investigation)

### Facts Confirmed

1. The CMIO registerassistant service daemon (`com.apple.cmio.registerassistantservice`) is what discovers camera extensions on macOS.
2. It uses **PlugInKit** (not ExtensionKit) for discovery.
3. The extension point identifier must be `com.apple.cmio.registerassistantservice`.
4. The Xcode product type must be `com.apple.product-type.app-extension` (NOT `com.apple.product-type.extensionkit-extension`).
5. The file reference type must be `wrapper.app-extension` (NOT `wrapper.extensionkit-extension`).
6. Info.plist must use `NSExtension` dict (NOT `EXExtensionAttributes`).
7. `CFBundlePackageType = "XPC!"` is correct for camera extensions.
8. The `CMIOExtension` dict with `CMIOExtensionMachServiceName` is required alongside `NSExtension`.
9. Mach service name format: `$(TeamIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` → `YOURTEAMID.io.github.loganrupe.CursorFollowMac.CameraExtension`.
10. App sandbox entitlement is required on the extension.
11. App groups must match between host and extension for IPC.
12. Extension binary entry point: `main.swift` calling `CMIOExtensionProvider.startService()` + `CFRunLoopRun()`.
13. The host app must be in `/Applications/` for extension discovery.
14. `pluginkit -mDAD -p com.apple.cmio.registerassistantservice` is the verification command.
15. Dylibs load correctly — the binary itself is structurally sound.

### What Failed in V1

| Issue | Detail |
|-------|--------|
| Wrong product type | `com.apple.product-type.extensionkit-extension` — pluginkit ignores these |
| Wrong extension point | `com.apple.camera-extension` via `EXExtensionAttributes` — CMIO daemon doesn't query this |
| Wrong file reference | `wrapper.extensionkit-extension` — affects bundle metadata |
| Patching deployed plist didn't help | Even after manually changing to `NSExtension`, the bundle wrapper type (baked in at build time) prevented discovery |
| `pluginkit -a` silently failed | Returned exit 0 but did not register |
| `lsregister -f` had no effect | LaunchServices registration doesn't trigger PlugInKit discovery for wrong-type bundles |

### Signing Configuration (Valid)

- Team: YOURTEAMID
- Host app ID: `io.github.loganrupe.CursorFollowMac`
- Extension ID: `io.github.loganrupe.CursorFollowMac.CameraExtension`
- App group: `group.io.github.loganrupe.CursorFollowMac`
- Authority: Apple Development: Logan Rupe (YOURCERTID)
- Hardened runtime: YES
- App sandbox: YES on both host and extension

## Functional Requirements

1. Camera extension registers with macOS and appears in `pluginkit -mDAD -p com.apple.cmio.registerassistantservice`.
2. Virtual camera device appears in `system_profiler SPCameraDataType`.
3. Camera is selectable in Photo Booth, FaceTime, Slack, Zoom.
4. Host app captures target window and delivers frames to extension via IPC.
5. Extension outputs stable 1920×1080 BGRA stream at configurable frame rate.
6. No crash/deadlock when target window changes, disappears, or app is closed.
7. Graceful degradation when permissions are missing.

## Non-Functional Requirements

1. Latency: <50 ms median from capture callback to CMIO stream output.
2. Stability: No memory growth or CPU spikes during 30-minute continuous capture.
3. Stream interruption on target switch: <300 ms.
4. Actionable log messages for transport, permissions, and discovery failures.

## Extension Info.plist (Correct Configuration)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CMIOExtension</key>
    <dict>
        <key>CMIOExtensionMachServiceName</key>
        <string>$(TeamIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    </dict>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.cmio.registerassistantservice</string>
    </dict>
</dict>
</plist>
```

## Extension Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.io.github.loganrupe.CursorFollowMac</string>
    </array>
</dict>
</plist>
```

## Xcode Target Configuration (Critical)

| Setting | Value |
|---------|-------|
| Product Type | `com.apple.product-type.app-extension` |
| File Reference Type | `wrapper.app-extension` |
| Bundle ID | `io.github.loganrupe.CursorFollowMac.CameraExtension` |
| INFOPLIST_FILE | Points to plist with `NSExtension` dict |
| GENERATE_INFOPLIST_FILE | YES |
| Embed Build Phase | "Embed App Extensions" (dstSubfolderSpec = 13) |
| ENABLE_APP_SANDBOX | YES |
| ENABLE_HARDENED_RUNTIME | YES |
| CODE_SIGN_STYLE | Automatic |
| DEVELOPMENT_TEAM | YOURTEAMID |

## Verification Commands

```bash
# 1. Check extension is registered
pluginkit -mDAD -p com.apple.cmio.registerassistantservice

# 2. Check camera device appears
system_profiler SPCameraDataType

# 3. Verify code signing
codesign -dvvv /Applications/CursorFollowMac.app/Contents/PlugIns/CameraExtension.appex

# 4. Verify entitlements
codesign -d --entitlements - /Applications/CursorFollowMac.app/Contents/PlugIns/CameraExtension.appex

# 5. Live logs
log stream --style compact --predicate 'eventMessage CONTAINS "CursorFollow" OR subsystem CONTAINS "cmio"'
```

## Acceptance Criteria

1. `pluginkit -mDAD -p com.apple.cmio.registerassistantservice` shows `io.github.loganrupe.CursorFollowMac.CameraExtension`.
2. `system_profiler SPCameraDataType` lists "CursorFollow Camera".
3. Photo Booth can select and display the virtual camera feed.
4. Build-deploy-verify cycle is documented and repeatable.
5. No manual `pluginkit -a` or hacks required — standard app launch triggers discovery.
