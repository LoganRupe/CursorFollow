# CursorFollowWin Phase 2: Window Tracking and Capture

## Phase 2 Status

Phase 2 is implemented as a Windows shareable-output-window slice layered on the Phase 1 tray app. It prioritizes enumerating capturable real app windows, capturing a selected listed window directly through Windows Graphics Capture HWND interop, and switching targets through automatic follow behavior while keeping the normal `CursorFollow Output` window stable for meeting-app sharing.

## Completed Behavior

- The tray panel refreshes a Win32 top-level window inventory.
- The inventory filters hidden, minimized, cloaked, tiny utility, shell/system, CursorFollow, and output-window surfaces by default.
- Refresh diagnostics summarize how many windows were shown versus omitted and list the most common omission reasons.
- Selecting a listed window and choosing `Start` or `Resume` captures that window directly through Windows Graphics Capture HWND interop.
- The existing Windows capture picker remains available when no tracked window is selected.
- Auto mode first tries the top-level window under the cursor with `WindowFromPoint`/`GetAncestor`, then falls back to the active foreground window.
- Auto-follow keeps a short debounce before switching capture targets to avoid capture thrash.
- Auto-follow runs as an app-level service from launch; the tray panel controls and reports it but does not own the follow loop.
- Automatic HWND capture requests Windows Graphics Capture programmatic access before calling `CreateForWindow`; picker capture can work without this because the picker grants access for the selected item.
- Automatic HWND capture creates `GraphicsCaptureItem` through `RoGetActivationFactory` and `IGraphicsCaptureItemInterop` with the HRESULT/out-pointer COM signature. Pass the explicit `IGraphicsCaptureItem` IID (`79C3F95B-31F7-4EC2-A464-632EF5D30760`) to `CreateForWindow`; using the managed class type GUID can fail at runtime with `No such interface supported`. Avoid casting the activation factory with `AsInterface`; that can fail with `Specified cast is not valid`.
- Filter mode is persisted as `All`, `Exclude`, or `Include`.
- `Include app` and `Exclude app` persist stable app identities and are respected by auto-follow and listed-window capture.
- App identity uses packaged app family name when Windows exposes it, executable path when available, and app/process name as fallback.
- The tray panel shows target mode and filter mode as compact segmented controls.
- Window rows show selected/captured/filter membership, title, app/process detail, window size, and `LIVE`/`IN`/`OUT`/`ALL` indicators.
- The panel exposes refresh, include selected app, exclude selected app, show/hide output, settings, quit, and resume/restart affordances.
- Capture startup failures do not mark the failed window as captured.
- If a target closes or capture fails, the output window stays open and moves to a fallback/error state instead of disappearing.
- Automatic target switches show the output window without activating it, so the output window does not steal focus from the app being followed.

## Build

From the repository root:

```powershell
dotnet build ./CursorFollowWin/CursorFollowWin.slnx -c Debug
```

## Verification Results

Validated in this workspace on 2026-06-04:

- `dotnet build ./CursorFollowWin/CursorFollowWin.slnx -c Debug` succeeded.
- `dotnet run --project ./CursorFollowWin/src/CursorFollowWin.App/CursorFollowWin.App.csproj -c Debug` launched successfully.
- Process smoke check found `CursorFollowWin.App` running with the `CursorFollow Output` window.
- Programmatic capture access is requested by the automatic follow path and denial details surface in output fallback/status text.

Desktop-only tray interactions still need manual verification on the local Windows session because the available automation in this run did not expose the system tray or desktop window surface for clicking or screenshot capture.

## Manual Phase 2 Verification

1. Launch the app.
2. Open two normal target windows, such as Notepad and Terminal.
3. Open the CursorFollow tray panel and choose `Refresh`.
4. Confirm the window list shows normal app windows and omits `CursorFollow Output`, CursorFollow's own windows, minimized windows, tiny/tool windows, and shell/system surfaces.
5. Confirm the panel status includes a shown/omitted refresh summary.
6. Select a listed target and choose `Start` or `Resume`.
7. Confirm the selected target renders in `CursorFollow Output` without opening the system capture picker.
8. Clear the selection if needed and choose `Start` or `Resume`; confirm the Windows capture picker fallback still opens.
9. Enable `Auto`, move the cursor over another allowed app, and confirm capture switches after the debounce interval.
10. With the cursor away from app windows, switch foreground focus to another allowed app and confirm foreground fallback switches capture after the debounce interval.
11. Add one app to `Exclude app`, switch to `Exclude`, and confirm manual capture and auto-follow skip that app.
12. Add one app to `Include app`, switch to `Include`, and confirm manual capture and auto-follow only allow included apps.
13. Close or minimize the current target and confirm `CursorFollow Output` remains open with a fallback/error status.
14. Save unrelated settings in the Settings dialog and confirm filter mode and app identities remain persisted in `%LocalAppData%\CursorFollowWin\settings.json`.

Suggested app coverage for verification:

- Normal Win32 apps: Notepad, Terminal, File Explorer.
- Electron apps: VS Code, Teams, Slack, or Discord if installed.
- Browsers: Edge, Chrome, Firefox if installed.
- Office apps: Word, Excel, PowerPoint if installed.
- Packaged/UWP apps: Settings or another Microsoft Store app where capture is permitted.

## Known Limitations

- Cursor-under-window follow uses the top-level HWND under the pointer and may fall back to foreground focus for elevated, protected, cloaked, or non-capturable surfaces.
- Some packaged/UWP apps still appear through `ApplicationFrameHost`; packaged family identity is captured only when Windows exposes it for the process handle.
- Protected/elevated windows can enumerate but fail Windows Graphics Capture startup; these failures surface as output fallback status.
- Windows can deny programmatic capture access by user or system policy. In that case, manual picker capture can still work, but automatic target follow cannot switch to HWND capture until access is allowed.
- Filter identity changes from executable path to packaged family name for packaged apps when available, so existing early-alpha filters for those apps may need to be re-added.
- Full cross-app manual verification remains pending for Electron, browsers, Office, and packaged apps on a desktop session with those apps installed.
- Global hotkeys, startup registration activation, installer flow, production diagnostics, and renderer optimization remain later-phase work.
