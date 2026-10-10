<p align="center">
  <img src="../Docs/images/app-icon.png" alt="CursorFollow app icon" width="128" height="128">
</p>

# CursorFollowLinux

CursorFollowLinux is the **Linux port** of CursorFollow. It captures a target window and
renders it into a normal, shareable GTK window called **CursorFollow Output**, so meeting
apps (Teams, Zoom, Slack, Google Meet, OBS) can share that one window while it keeps
following whatever you are working in.

Like the Windows port it is **output-window-first**: there is no virtual camera.

> New here? The [project overview](../README.md) describes the controls shared by all three
> ports. The macOS app is the reference implementation: [CursorFollowMac](../CursorFollowMac/README.md).

---

## Status

First working build. What is in:

- **Per-window capture** through `hyprland_toplevel_export_v1`, straight from the
  compositor, with no portal picker. Frames land in shared memory and go to the GTK
  renderer without an extra copy.
- **Window tracking** over Hyprland's IPC sockets: the list, the focused window, and
  live events (open, close, title, focus) so the list stays current without polling.
- **Auto / Manual target mode**, **All / Exclude / Include** filters keyed on the
  window's `app_id` (the Hyprland "class"), 150 ms focus debounce, and self-capture
  exclusion.
- **Output window** states matching the other ports (no target, paused, unavailable,
  preparing, live), **Fit / Fill / Actual** scaling, resolution and fps overlays.
- **Control panel** and **settings window**, settings persisted as a key file.
- **CLI remote control** for compositor key bindings (`--toggle-follow`, `--toggle-output`,
  `--pause`, `--resume`, `--toggle-capture`, `--show-panel`, `--settings`, `--quit`) through the
  single-instance D-Bus name.
- **Start on login** via an XDG autostart entry; **pin on top** via Hyprland's float + pin.

What is not in yet:

- **Other compositors.** Capture and tracking are Hyprland-only for now. The standard
  `ext-image-copy-capture-v1` + `ext-foreign-toplevel-list-v1` pair (Hyprland, Sway,
  niri, KWin) is the planned second backend; the engine is isolated so that can slot in.
- **Capture scaling** (the macOS 50/75% option). The toplevel-export protocol hands back
  the window's native size.
- **dmabuf transport.** The compositor offers it; the engine uses `wl_shm` for now.
- **System tray icon.** Hyprland setups vary too much (waybar, omarchy-shell, none);
  the panel is a normal window and the CLI covers key bindings.
- Packaging (PKGBUILD / Flatpak) and a global-shortcuts portal integration.

---

## Requirements

- **Hyprland** (tested on 0.56). The compositor must export
  `hyprland_toplevel_export_manager_v1`; check with `wayland-info` if unsure.
- **GTK 4** (4.14 or newer), **json-glib**, **wayland-client**.
- Build tools: `g++` (C++20), `make`, `pkg-config`, `wayland-scanner`.

Arch / Omarchy:

```sh
sudo pacman -S --needed gtk4 json-glib wayland gcc make pkgconf
```

Debian / Ubuntu:

```sh
sudo apt install libgtk-4-dev libjson-glib-dev libwayland-dev wayland-protocols g++ make pkg-config
```

No permissions dialog: Hyprland's export protocol does not go through the portal.

---

## Build, test, run

From this directory:

```sh
make -j"$(nproc)"      # -> build/cursorfollow
make test              # unit tests for the filter, settings and Hyprland JSON parsing
make run               # or ./build/cursorfollow
```

Install for the current user (binary, desktop entry, icon under `~/.local`):

```sh
make install           # PREFIX=/usr/local for a system-wide install
make uninstall
```

The protocol XML files are vendored under `protocols/` and turned into C at build time
with `wayland-scanner`, so no `hyprland-protocols` package is needed.

---

## Using it

1. Launch **CursorFollow**. The panel and the **CursorFollow Output** window appear; the
   output shows *No Target Selected* until you start capture.
2. Press **Resume**. In **Auto** mode it follows the focused window; in **Manual** mode it
   captures the window you clicked in the list.
3. In your meeting app, share the window named **CursorFollow Output**.

Panel controls:

| Control | What it does |
| --- | --- |
| **Auto / Manual** | Auto follows focus; Manual keeps the selected window. |
| **All / Exclude / Include** | Which apps auto-follow may switch to. In Exclude or Include, clicking a row toggles that app's membership; right-click switches to it regardless. |
| **Refresh** | Re-read the window list (it also updates on compositor events). |
| **Show / Hide** | Show or hide the output window. Closing it also just hides it. |
| **Resume / Pause** | Start or stop capture without changing the output window's identity. |

Settings (gear icon) apply immediately: start on login, auto share on start, hide when
not sharing, pin output on top, resolution and fps overlays, output scaling, and the
capture-quality preset (frame-rate ceiling; frames are only copied when the target
changes, so a static window costs nothing).

### Key bindings

Global shortcuts live in the compositor. Each command talks to the running instance and
starts it if needed. Hyprland (Omarchy `~/.config/hypr/bindings.lua`):

```lua
o.bind("CTRL + ALT + F", "CursorFollow: toggle auto-follow", "cursorfollow --toggle-follow")
o.bind("CTRL + ALT + S", "CursorFollow: toggle output", "cursorfollow --toggle-output")
```

Classic `hyprland.conf` syntax:

```ini
bind = CTRL ALT, F, exec, cursorfollow --toggle-follow
bind = CTRL ALT, S, exec, cursorfollow --toggle-output
```

### Window rules

Both CursorFollow windows use the app id `io.github.loganrupe.CursorFollowLinux`. A floating panel
is usually nicer on a tiling layout:

```lua
hl.window_rule({ name = "cursorfollow-panel", match = { class = "^io.github.loganrupe.CursorFollowLinux$", title = "^CursorFollow$" }, float = true, size = { 360, 640 } })
```

Leave the output window tiled or floating as you prefer; **Actual** scaling only resizes
it when it floats.

---

## Configuration

Settings are a GLib key file at `~/.config/CursorFollowLinux/settings.ini`:

| Key | Default | Meaning |
| --- | --- | --- |
| `autoShareOnStart` | `false` | Start following the focused window at launch |
| `hideWhenNotSharing` | `false` | Hide the output window while capture is stopped |
| `pinOutputOnTop` | `false` | Float and pin the output window |
| `showResolution` / `showFrameCount` | `false` | Overlays on the output |
| `outputPresentationMode` | `fit` | `fit`, `fill` or `actualSize` |
| `captureQuality` | `balanced` | `balanced` (30 fps), `smooth` (60), `efficient` (15) |
| `autoFollowEnabled` | `true` | Target mode |
| `filterMode` | `All` | `All`, `Exclude` or `Include` |
| `excludedApps` / `includedApps` | empty | `app_id` lists for the filter modes |

Start on login is the presence of `~/.config/autostart/io.github.loganrupe.CursorFollowLinux.desktop`.
Delete the settings file to reset.

Logs go to stderr (and the journal when launched from the desktop). Set
`G_MESSAGES_DEBUG=CursorFollow` for per-frame and per-window detail.

---

## How it works

```text
src/
├── main.cpp             GtkApplication, single instance, CLI flags -> actions
├── app.*                Coordinator: wires tracker, engine and windows (AppCoordinator on macOS)
├── window_tracker.*     Hyprland IPC: window list, focus events, debounce, selection
├── hyprland_ipc.*       .socket.sock requests and .socket2.sock event stream
├── hyprland_clients.*   json-glib parsing of `hyprctl -j clients` / `activewindow`
├── window_filter.*      Pure All/Exclude/Include logic (unit-tested)
├── capture_engine.*     hyprland_toplevel_export_v1 -> wl_shm -> GdkMemoryTexture
├── output_window.*      The shareable "CursorFollow Output" window and its states
├── panel_window.*       Control panel
├── settings_window.*    Settings
├── app_settings.*       Key-file settings store, autostart entry
└── tracked_window.*     TrackedWindow value type, FilterMode
```

Capture loop: request a frame for the target's address, let the compositor pick the
buffer format, copy into a pooled `wl_shm` buffer, wrap that memory in a `GdkTexture`
and hand it to the picture widget. The buffer returns to the pool when GTK releases the
texture. After the first frame the copy waits for damage, so an idle target costs no CPU;
the quality preset caps how often a busy target is copied.

Self-capture is excluded twice: the tracker drops windows with our own `app_id`, and the
title `CursorFollow Output` is rejected on its own.

---

## Troubleshooting

- **"Capture Unavailable" in the output window.** The compositor does not export
  `hyprland_toplevel_export_manager_v1`. Only Hyprland is supported today.
- **"Hyprland IPC socket not found".** `HYPRLAND_INSTANCE_SIGNATURE` is not set in the
  environment the app was launched from. Launch it from the session (a key binding, the
  app launcher, or a terminal inside Hyprland).
- **Frames stop, every screen capture tool hangs, `hyprctl` still works.** The output
  stopped page-flipping (look for `flip_done timed out` in `journalctl -k`). Cycling
  `hyprctl dispatch dpms off` then `on` re-initialises the display.
- **The meeting app shows a stale picture.** Re-pick **CursorFollow Output** in its
  share picker; the window keeps the same identity, so this is rarely needed.
- **Target Unavailable.** The window closed. In Auto mode the next focused window takes
  over; in Manual mode pick another one.
