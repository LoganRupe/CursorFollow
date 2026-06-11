# CursorFollowWin Output Window Capture Proof

## What Was Built

Phase 0 plus the early WGC proof replaced generated test frames with a minimal Windows Graphics Capture path in `src/CursorFollowWin.App`. Phase 1 now layers the tray-resident shell around this proof; see `Phase1TrayUi.md` for the tray and settings verification checklist.

The app still opens a normal Windows desktop window titled `CursorFollow Output`. Users manually choose a target through the Windows capture picker, and CursorFollow renders the captured frames into the same shareable WinUI output window. The output surface resizes to the captured content dimensions and is hosted in the existing aspect-preserving `Viewbox`, so window resizing keeps the target content proportional with letterboxing as needed.

This proof intentionally remains output-window-first. Phase 1 adds tray UI and basic persisted settings, but it still does not include a virtual camera, installer, global hotkeys, automatic target tracking, full window enumeration, or production renderer tuning.

## How To Build

From the repository root:

```powershell
dotnet build ./CursorFollowWin/CursorFollowWin.slnx -c Debug
```

## How To Run

From the repository root:

```powershell
dotnet run --project ./CursorFollowWin/src/CursorFollowWin.App/CursorFollowWin.App.csproj -c Debug
```

Expected result: a window titled `CursorFollow Output` appears with a `Select target` button and a fallback message.

## Manual Capture Verification

1. Start the CursorFollowWin app.
2. Open a normal target app window, such as Notepad, Terminal, or a browser tab.
3. In CursorFollow, choose `Select target`.
4. In the Windows capture picker, select the target window.
5. Confirm the selected target appears inside `CursorFollow Output` and the frame counter changes.
6. Resize `CursorFollow Output` and confirm the captured target remains visible and aspect-preserved.
7. Resize the target window and confirm CursorFollow continues rendering frames after the captured content size changes.
8. Close the target window and confirm CursorFollow returns to a fallback state.
9. Choose `Select target` again and confirm a different target can be captured.
10. Choose `Stop` and confirm live frames clear from the output window.
11. Choose `Select target`, select `CursorFollow Output`, and confirm CursorFollow rejects the self-capture target instead of starting recursive capture.

## Manual Share Verification

The Phase 1 product question is whether users can keep their real webcam selected in meeting apps while sharing the `CursorFollow Output` window that now contains a live captured target.

For each app below:

1. Start the CursorFollowWin app and select a target window.
2. Confirm the frame counter changes and target content is visible in `CursorFollow Output`.
3. Start or join a test meeting/session.
4. Keep the real webcam selected as the camera source.
5. Start screen sharing and choose window sharing.
6. Select `CursorFollow Output`.
7. Confirm participants or preview output see the captured target content.
8. Resize the CursorFollow output window and confirm shared content remains aspect-preserved.
9. Resize or update the target window and confirm the shared output continues changing.
10. Stop sharing and confirm the real webcam selection was not replaced by CursorFollow.

Compatibility matrix to fill during manual testing:

| App                   | Window listed? | Real webcam remains selected? | Captured frames visible? | Resize OK? | Target resize OK? | Notes                                                        |
| --------------------- | -------------- | ----------------------------- | ------------------------ | ---------- | ----------------- | ------------------------------------------------------------ |
| Microsoft Teams       | Not tested     | Not tested                    | Not tested               | Not tested | Not tested        |                                                              |
| Zoom                  | Not tested     | Not tested                    | Not tested               | Not tested | Not tested        |                                                              |
| Slack                 | Yes            | Yes                           | Yes                      | Not tested | Not tested        | Phase 1 live captured output shared successfully over Slack. |
| Google Meet in Chrome | Not tested     | Not tested                    | Not tested               | Not tested | Not tested        |                                                              |
| Google Meet in Edge   | Not tested     | Not tested                    | Not tested               | Not tested | Not tested        |                                                              |
| OBS Window Capture    | Not tested     | Not tested                    | Not tested               | Not tested | Not tested        |                                                              |

## Known Limitations

- Target selection is manual through the Windows capture picker. There is no active-window follow, cursor-adjacent target switching, or custom target list yet.
- The renderer copies each WGC frame through `SoftwareBitmap` into a XAML image. This is simple and inspectable, but it is not the final low-latency Direct3D/Win2D rendering path.
- Captured frames include the cursor when the Windows Graphics Capture session supports cursor capture.
- Minimized, protected, elevated, DRM, secure desktop, or otherwise restricted windows may produce blank, stale, or unavailable frames depending on Windows policy.
- The Windows capture picker can still list `CursorFollow Output`, but CursorFollow rejects that selection before starting capture so the output window stays shareable in meeting apps.
- The visible control strip remains in the same output window for this proof. A future product UI should separate control surface behavior from the shareable output surface if meeting-app sharing requires a cleaner frame.
- The app is still an unpackaged WinUI debug prototype, not an installer-ready product.
- Phase 1 adds tray lifecycle, pin-on-top, and basic settings persistence, but logging, diagnostics surface, global hotkeys, full target tracking, and virtual camera support remain out of scope.

## Next Steps

1. Run the manual capture verification above on Windows 11 with multiple target apps and DPI/resizing scenarios.
2. Continue filling the meeting-app compatibility matrix with live captured content.
3. Move output rendering from CPU `SoftwareBitmap` copies to a Win2D or Direct3D-backed surface if latency, CPU usage, or frame pacing are not acceptable.
4. Add output-window exclusion and a small window inventory before implementing auto-follow target switching.
5. Add diagnostics for target selection, capture stop reasons, frame size changes, and renderer errors.
