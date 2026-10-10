# Changelog

## Unreleased

## 0.5.1

First public release of **CursorFollow**, open source under the MIT License at [github.com/LoganRupe/CursorFollow](https://github.com/LoganRupe/CursorFollow). Runs on **macOS**, **Windows** and **Linux (Hyprland)**.

CursorFollow captures a target window and renders it into a stable, shareable window named **CursorFollow Output**. Share that one window in Zoom, Google Meet, Slack, Teams, OBS, or any app with a window-share picker, and it keeps following your target as you switch focus, so your audience always sees the right thing without you re-picking a share source.

### Highlights

- **Shared output window** — a single persistent **CursorFollow Output** window you share once and keep, while you keep your real webcam selected.
- **Target Mode** — **Auto** tracks the active eligible window; **Manual** locks to a window you pick.
- **Window filtering** — **All / Include / Exclude** modes control which windows show up as capture targets.
- **Output scaling** — **Fit**, **Fill**, or **Actual** sizing for the shared window.
- **Background app** — runs in the macOS **menu bar** / Windows **system tray** with a compact control panel and settings.
- **Global hotkeys** and **Show / Hide**, **Resume / Pause**, and **Refresh** controls.

### macOS

- Window capture via **ScreenCaptureKit**; requires the **Screen Recording** permission on first launch.
- Sandboxed menu bar app for macOS 14 Sonoma and later.
- Signed with a self-signed certificate, not notarized. Approve the first launch in **System Settings → Privacy & Security → Open Anyway**; updates after that open normally and keep the Screen Recording grant.
- Distributed as a drag-to-**Applications** `.dmg`.

### Windows

- Window capture via **Windows Graphics Capture** + Direct3D 11, with zero-copy GPU frame transport.
- Auto-follow (cursor-under-window with foreground fallback), live frame telemetry, and single-instance guard.
- Global hotkeys, Start-with-Windows, and capture-quality presets.
- Distributed as a per-user **WiX MSI** installer (no admin required; clean upgrade and uninstall).

### Linux

- First working build of **CursorFollowLinux**: GTK 4 control panel and shared output window, per-window capture through Hyprland's toplevel-export protocol, auto-follow over Hyprland IPC, All / Include / Exclude filters, Fit / Fill / Actual scaling, key-file settings, and CLI flags for compositor key bindings. Hyprland only for now; see `CursorFollowLinux/README.md`.

### Coming from the internal 1.0 build

- The macOS bundle ID is now `io.github.loganrupe.CursorFollowMac`, so macOS treats 0.5.1 as a new app: settings start fresh and Screen Recording is asked for again. Delete the old app from **Applications**.
- On Windows, uninstall 1.0 first; the MSI refuses to install over a higher version number. Uninstalling also clears 1.0's settings, so you start fresh.
