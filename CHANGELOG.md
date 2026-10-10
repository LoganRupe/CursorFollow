# Changelog

## Unreleased

### Project

- CursorFollow is now open source under the MIT License, hosted at [github.com/LoganRupe/CursorFollow](https://github.com/LoganRupe/CursorFollow).
- New app identifiers: the macOS bundle ID is `io.github.loganrupe.CursorFollowMac` and the Linux app id is `io.github.loganrupe.CursorFollowLinux`. On macOS, upgrading from 1.0 starts with default settings and asks for Screen Recording again. On Linux, re-enable **Start on login** once. The Windows publisher is now Logan Rupe; Windows settings carry over.

### macOS

- Runs on macOS 14 Sonoma and later (1.0 needed macOS 26.4).
- Releases are signed with a self-signed certificate and are no longer notarized. Approve the first launch in **System Settings → Privacy & Security → Open Anyway**; updates after that open normally and keep the Screen Recording grant.

### Linux

- First working build of **CursorFollowLinux**: GTK 4 control panel and shared output window, per-window capture through Hyprland's toplevel-export protocol, auto-follow over Hyprland IPC, All / Include / Exclude filters, Fit / Fill / Actual scaling, key-file settings, and CLI flags for compositor key bindings. Hyprland only for now; see `CursorFollowLinux/README.md`.

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
