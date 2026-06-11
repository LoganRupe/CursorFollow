# CursorFollowWin Phase 1: Project Skeleton and Tray UI

## What Phase 1 Adds

Phase 1 keeps the existing output-window-first Windows Graphics Capture proof working and adds the smallest practical tray-resident app shell around it.

- A Windows notification-area icon appears while the app is running.
- Left-clicking the tray icon opens a compact CursorFollow panel near the bottom-right taskbar area.
- The compact panel exposes the Phase 1 workflow surface: Auto-follow, filter mode, window row, Refresh, Show/Hide output, status, Start, Stop, Settings, and Quit.
- Start opens the existing Windows capture picker and renders the selected target into `CursorFollow Output`.
- Stop stops the existing WGC capture proof without destroying the output window.
- Show/Hide output controls the normal shareable output window.
- Settings opens a shell dialog with General, Capture Quality, Hotkeys, Display, and persisted per-user settings.
- The output window still rejects `CursorFollow Output` as its own capture target.

The tray panel intentionally marks auto-follow, filter modes, and full window enumeration as later-phase scaffolding. Manual target selection through the Windows capture picker remains the working Phase 1 capture path.

## Build

From the repository root:

```powershell
dotnet build ./CursorFollowWin/CursorFollowWin.slnx -c Debug
```

## Run

From the repository root:

```powershell
dotnet run --project ./CursorFollowWin/src/CursorFollowWin.App/CursorFollowWin.App.csproj -c Debug
```

Expected launch result:

- `CursorFollow Output` opens as a normal shareable window.
- A `CursorFollowWin` tray icon appears in the notification area or overflow menu.
- The app remains available through the tray while the output window is shown or hidden.

## Manual Phase 1 Verification

1. Launch the app.
2. Confirm the `CursorFollow Output` window appears and still shows the existing fallback/select-target state.
3. Find the `CursorFollowWin` tray icon and left-click it.
4. Confirm the compact panel opens near the bottom-right taskbar area.
5. Confirm the panel includes Auto-follow, filter mode, window row, Refresh, Show/Hide output, status, Start, Stop, Settings, and Quit controls.
6. Choose `Start` from the panel.
7. Select a normal target window in the Windows capture picker.
8. Confirm captured frames render in `CursorFollow Output`.
9. Choose `Stop` from the panel and confirm capture stops with the output window still available.
10. Choose `Hide output`, then `Show output`, and confirm the output window visibility follows the panel state.
11. Choose `Settings`, change `Pin output on top` or `Show overlay`, and save.
12. Quit and relaunch the app, then confirm settings persisted under `%LocalAppData%\CursorFollowWin\settings.json`.
13. Choose `Start`, select `CursorFollow Output`, and confirm the app rejects self-capture.
14. In Slack or another meeting app, confirm `CursorFollow Output` is still shareable while the real webcam remains selected.

## Persisted Settings

Settings are stored per Windows user at:

```text
%LocalAppData%\CursorFollowWin\settings.json
```

Phase 1 persists the shell values needed by the settings dialog. Startup registration, hotkey registration, and production capture-quality behavior are not activated yet.

## Still Out of Scope

The following items remain for later phases from `Requirements.html`:

- Full visible-window enumeration and custom window list refresh.
- Foreground-window or cursor-under-window auto-follow.
- Include and exclude filtering behavior.
- Global hotkey registration and conflict handling.
- Installer, startup registration, upgrade, uninstall, and reset flows.
- Production renderer optimization beyond the current WGC proof path.
- Virtual camera work.

## Known Limitations

- The tray icon opens the panel on left click; a full native tray context menu can be added later if product testing calls for it.
- The panel window is a minimal WinUI shell, not final visual parity with the macOS panel.
- The output window still contains the proof controls; separating control UI from the shareable surface is a later product polish task.
- Closing WinUI windows with their title-bar close buttons is not yet hardened into final tray-resident lifecycle behavior.
- `Start with Windows`, `Auto-share on launch`, `Hide when not sharing`, and `Capture Quality` are persisted settings only in Phase 1.
