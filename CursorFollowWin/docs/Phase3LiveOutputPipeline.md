# CursorFollowWin Phase 3: Live Output Pipeline

## Phase 3 Status

Phase 3 strengthens the shareable-output-window path built in Phases 1 and 2. The app still uses the simple CPU `SoftwareBitmap` copy renderer, but the output pipeline now reports useful live telemetry, keeps the shared window cleaner while frames are live, and routes manual and automatic capture through the same target-follow service.

## Completed Behavior

- Manual listed-window capture and automatic target follow now use the shared `TargetFollowService` instead of separate tray-panel and app-level follow loops.
- The app now opens `CursorFollow Output` on launch by default.
- A named single-instance guard prevents multiple `CursorFollowWin.App` processes; a duplicate launch restores and focuses the existing output window.
- Auto-follow still tries the top-level window under the cursor before falling back to the foreground window.
- Captured-window state is owned by the follow service, so the tray list can consistently mark the live target.
- The Windows Graphics Capture controller tracks dropped frames when a previous frame is still being processed.
- Captured frames carry CPU copy duration and dropped-frame count into the output renderer.
- The output page computes a smoothed frame rate and render-latency estimate for the live status line.
- The output window control strip is hidden while live frames are rendering, making the shared window less cluttered during meeting-app sharing.
- Idle, stopped, target-closed, protected-content, and renderer-error states still keep the normal `CursorFollow Output` window available with fallback text.
- `Hide when not sharing` now applies when capture state changes, not only during launch/settings changes.
- Pin-on-top and taskbar-icon settings continue to apply through the output window wrapper.

## Build

From the repository root:

```powershell
dotnet build ./CursorFollowWin/src/CursorFollowWin.App/CursorFollowWin.App.csproj
```

Validated in this workspace on 2026-06-05 after stopping a stale running `CursorFollowWin.App` instance that locked the output executable.

## Manual Phase 3 Verification

1. Launch the app.
2. Open the tray panel and select a normal target window.
3. Choose `Resume` and confirm the selected target renders in `CursorFollow Output`.
4. Confirm the bottom output-window control strip hides while live frames are visible.
5. Confirm the live status text reports frame size, estimated fps, copy latency, render latency, and dropped frames.
6. Resize the target window and confirm the output surface preserves aspect ratio and updates the reported frame size.
7. Resize `CursorFollow Output` and confirm the captured content remains aspect-preserved.
8. Enable Auto mode and confirm target changes still debounce and do not activate the output window during automatic switches.
9. Stop capture and confirm the output window returns to the fallback/select-target state without closing.
10. Close the captured target and confirm the output window remains open with a fallback/error message.
11. Enable `Hide when not sharing`, stop capture, and confirm the output window hides/minimizes according to the taskbar-icon setting.
12. Enable `Pin output on top` and confirm the output window stays above normal app windows.
13. Share `CursorFollow Output` in a meeting app and confirm live content is visible while the real webcam remains selected.

## Known Limitations

- Rendering still uses `SoftwareBitmap.CreateCopyFromSurfaceAsync` and `SoftwareBitmapSource`, so GPU texture sharing and lower-latency Direct3D/Win2D rendering remain future optimization work.
- Latency telemetry is an in-app estimate around copy and UI presentation, not a full end-to-end photometric measurement.
- Dropped-frame counts only represent frames skipped because the previous software-copy path was still busy.
- The visible telemetry overlay is controlled by `Show overlay`; disable it before meeting-app sharing if a clean output frame is preferred.
- Desktop tray and meeting-app sharing verification remain manual because automated UI access to the Windows notification area and conferencing clients is not available in this workspace.

## Next Steps

1. Run the manual Phase 3 verification on the local Windows desktop session with Notepad, Terminal, a browser, and at least one Electron app.
2. Fill the meeting-app compatibility matrix in `OutputWindowFeasibility.md` with Phase 3 live telemetry enabled and disabled.
3. If copy or render latency is too high, replace the software bitmap renderer with a Win2D or Direct3D-backed output surface.
