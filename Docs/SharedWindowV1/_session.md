# Session: SharedWindowV1

## Current Phase

- Phase 4: Controls, Status, and Validation

## 2026-06-03 Phase 4 Implementation Notes

- Added first-level menu bar controls for target mode, output show/hide, and pause/resume language.
- Kept output scaling in the existing Settings modal instead of duplicating it in the compact menu panel.
- Added direct System Settings repair only for Screen Recording errors; removed the misleading Accessibility prompt because CursorFollow was not present in that Settings pane.
- Resized the menu popover back to a compact height after moving non-call-critical controls out of it.
- Updated user-facing README copy from the virtual-camera workflow to the shared-window workflow.
- Updated capture/transport comments so the active path is described as host output-window rendering.

## Phase 4 Remaining Gates

- Validate that `CursorFollow Output` can be shared in Zoom, Google Meet, Slack Huddles, or Teams.
- Run a 30-minute continuous share test and record CPU, memory, and visual stability notes.

## Phase 4 Validation

- Editor diagnostics are clean for Phase 4 touched Swift files.
- `xcodebuild test -project CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:CursorFollowMacTests` succeeded.
- `xcodebuild -project CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' build` succeeded.

## 2026-06-03 Settings Audit Notes

- Verified Settings save/cancel behavior and runtime consumers for general, display, capture quality, and hotkey settings.
- Fixed saved output display preferences so Pin on top, output overlays, and scaling apply during app startup before the menu popover is opened.
- Renamed Settings copy from sharing/minimize language to Shared Window V1 output language.
- Added focused tests for loading saved output preferences and falling back to Fit when a saved presentation mode is invalid.
- Rebuilt, redeployed, and relaunched `/Applications/CursorFollowMac.app` after the settings audit fix.

## 2026-06-03 Phase 3 Implementation Notes

- Centralized the always-excluded bundle ID rule so CursorFollow-owned windows and system UI windows are filtered from capture candidates consistently.
- Added a target-unavailable signal when the selected window disappears, minimizes, or moves to another Space.
- Routed target-unavailable state through `AppCoordinator` so the persistent output window shows an explicit fallback state and stops stale capture.
- Clear target-unavailable state on successful manual or auto-follow selection.
- Added focused tests for CursorFollow/system-window exclusion and unavailable-target recovery messaging.

## Phase 3 Validation

- Editor diagnostics are clean for `CursorFollowMac/CursorFollowMac` and `CursorFollowMac/CursorFollowMacTests`.
- `xcodebuild test -project /Users/loganrupe/repos/CursorFollow/CursorFollowMac/CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:CursorFollowMacTests` succeeded.
- Local stale-binary-safe build/deploy one-liner completed successfully and launched `/Applications/CursorFollowMac.app`.

## Phase 3 Remaining Gate

- Manually verify repeated target switching in the running app without recursion, crashes, or conferencing share-source loss.
- Manually verify closing, minimizing, or moving the selected target to another Space shows the Target Unavailable fallback instead of a stale frame.

## 2026-06-03 Phase 2 Implementation Notes

- Connected captured-frame delivery directly to the output surface refresh path so the output window presents the latest frame instead of refreshing continuously on a display link.
- Reworked the output renderer to use a black hosting layer plus a dedicated IOSurface content layer with predictable crop and layout behavior.
- Added output scaling modes: fit, fill, and actual size.
- Persisted output scaling in app settings and surfaced it in the Display settings section.
- Updated ScreenCaptureKit capture sizing to account for the target screen backing scale while staying within the shared IOSurface bounds.
- Sized the output window from capture points rather than raw pixels to keep Retina targets visually consistent.
- Fixed target switches resizing `CursorFollow Output`; capture updates now change only the renderer crop/scale metadata and preserve the existing output window size.
- Refined scaling behavior so only Actual mode intentionally resizes `CursorFollow Output`; Fit and Fill preserve the current shared-window size.

## Phase 2 Validation

- `xcodebuild -project CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' build` succeeded.
- `xcodebuild test -project /Users/loganrupe/repos/CursorFollow/CursorFollowMac/CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -destination 'platform=macOS,arch=arm64' -only-testing:CursorFollowMacTests` succeeded.

## Phase 2 Remaining Gate

- Manually verify that selected target window content appears live in `CursorFollow Output` with acceptable quality in fit, fill, and actual-size modes.

## 2026-06-03 Phase 1 Implementation Notes

- Added explicit output-window states for no target, missing permissions, paused output, target unavailable, waiting for first frame, and live output.
- Kept `CursorFollow Output` as one persistent `NSWindow` instance across target and capture state changes.
- Show the output window on launch by default unless the existing hide-when-not-sharing preference is enabled.
- Routed selected-window, capture, and permission/error changes through `AppCoordinator` so the output window updates even when the menu popover is closed.
- Removed launch-time camera extension activation and removed the app target's dependency on/embedding of the camera system extension. The historical `CameraExtension` target remains in the project.

## Validation

- `xcodebuild -project CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug build` succeeded.
- `xcodebuild test -project CursorFollowMac.xcodeproj -scheme CursorFollowMac -configuration Debug -only-testing:CursorFollowMacTests` succeeded.
- Full scheme test currently fails in the stock UI launch-performance test: `CursorFollowMacUITests.testLaunchPerformance()`.

## Remaining Gate

- Manually verify that `CursorFollow Output` appears as a selectable window in a conferencing app or browser share picker.