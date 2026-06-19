# Changelog

## Version 1.0 (Build 1)

First release of **CursorFollow** for **macOS** and **Windows**.

CursorFollow captures a target window and renders it into a stable, shareable window named **CursorFollow Output**. Share that one window in Zoom, Google Meet, Slack, Teams, OBS, or any app with a window-share picker, and it keeps following your target as you switch focus — so your audience always sees the right thing without you re-picking a share source.

### Highlights

- **Shared output window** — a single persistent **CursorFollow Output** window you share once and keep, while you keep your real webcam selected.
- **Target Mode** — **Auto** tracks the active eligible window; **Manual** locks to a window you pick.
- **Window filtering** — **All / Include / Exclude** modes control which windows show up as capture targets.
- **Output scaling** — **Fit**, **Fill**, or **Actual** sizing for the shared window.
- **Background app** — runs in the macOS **menu bar** / Windows **system tray** with a compact control panel and settings.
- **Global hotkeys** and **Show / Hide**, **Resume / Pause**, and **Refresh** controls.

### macOS

- Window capture via **ScreenCaptureKit**; requires the **Screen Recording** permission on first launch.
- Sandboxed menu bar app, signed and notarized for distribution outside the App Store.
- Distributed as a drag-to-**Applications** `.dmg`.

### Windows

- Window capture via **Windows Graphics Capture** + Direct3D 11, with zero-copy GPU frame transport.
- Auto-follow (cursor-under-window with foreground fallback), live frame telemetry, and single-instance guard.
- Global hotkeys, Start-with-Windows, and capture-quality presets.
- Distributed as a per-user **WiX MSI** installer (no admin required; clean upgrade and uninstall).
