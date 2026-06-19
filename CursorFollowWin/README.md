<p align="center">
  <img src="../Docs/images/app-icon.png" alt="CursorFollow app icon" width="128" height="128">
</p>

# CursorFollowWin

CursorFollowWin is the **Windows port** of CursorFollow. It tracks a target window on
your desktop and exposes that capture as a normal, shareable WinUI window so meeting and
recording apps (Teams, Zoom, Slack, Google Meet, Edge, OBS) can share the tracked surface
while you keep your real webcam selected.

The Windows product is **output-window-first**: the primary deliverable is the shareable
output window, not a virtual camera. A Windows virtual-camera mode is explicitly optional
and out of scope for the current phases (see [Status](#status)).

> New here? See the [project overview](../README.md) for what CursorFollow does and the controls
> shared with the macOS app. The mature, full-featured sibling is [CursorFollowMac](../CursorFollowMac/README.md);
> this directory is the Windows-native rebuild.

---

## Status

Single WinUI 3 desktop project (~3,300 LOC). Implemented so far:

- **WGC proof** — Windows Graphics Capture renders a selected window into the
  "CursorFollow Output" window. Self-capture is rejected.
- **Phase 1 — Tray UI** — `Shell_NotifyIcon` tray icon, compact panel, settings dialog,
  versioned JSON settings.
- **Phase 2 — Window tracking** — Win32 window enumeration + filtering, direct `HWND`
  capture via `IGraphicsCaptureItemInterop`, auto-follow (cursor-under-window with
  foreground fallback, 350 ms debounce), and `All` / `Include` / `Exclude` filter modes.
- **Phase 3 — Live pipeline** — unified `TargetFollowService` for manual and auto target
  selection, frame telemetry (fps / copy / render latency / dropped frames), single-instance
  guard.
- **Phase 3.5 — Gap close-out** — real global hotkeys (`RegisterHotKey`), Start-with-Windows
  (HKCU `Run` key), capture-quality presets, output scaling (Fit / Fill / Actual),
  pin/hide behavior, file-based diagnostics, and accessibility names. Plus the structural split
  into `.Shared` / `.Capture` / `.Output` projects with xUnit tests, and zero-copy GPU frame
  transport (swap-chain present, ~0.4 ms pipeline latency).
- **Phase 4 — Packaging & hardening** — a per-user **WiX MSI installer** (no UAC; upgrade path,
  uninstall cleanup), developer build/publish/package/verify scripts, a code-signing plan, and
  reset/troubleshooting docs. See [docs/Installer.md](docs/Installer.md).

**Not yet done:** code signing (planned and wired — see
[docs/CodeSigning.md](docs/CodeSigning.md) — but no certificate yet) and the full meeting-app
compatibility matrix (Slack is confirmed; the rest is descoped for now). See [docs/](docs/) for
the per-phase records.

---

## Tech stack

| Area        | Choice                                              |
| ----------- | --------------------------------------------------- |
| Runtime     | .NET 10 (LTS)                                        |
| Language    | C# (latest supported by .NET 10)                    |
| UI          | WinUI 3 via the Windows App SDK (unpackaged)        |
| Target OS   | Windows 11, build 22000+                             |
| Capture     | Windows Graphics Capture + Direct3D 11              |
| Rendering   | `Microsoft.Graphics.Win2D`                          |
| Logging     | `Microsoft.Extensions.Logging` + rolling file sink  |
| Platforms   | `x64` (primary), `x86`, `ARM64`                      |

See [TechStack.md](TechStack.md) for the full rationale and the longer-term architecture plan.

---

## Repository layout

This project is a single, flat WinUI 3 app. The most relevant files:

```text
CursorFollowWin/
├── CursorFollowWin.slnx               # Solution (XML-based .slnx)
├── CursorFollowWin.csproj             # The app project (produces CursorFollowWin.exe)
├── App.xaml(.cs)                      # App entry point, single-instance guard, wiring
├── MainWindow.xaml(.cs)               # The shareable "CursorFollow Output" window
├── PanelWindow.xaml(.cs)              # Compact tray panel
├── SettingsWindow.xaml.cs             # Settings dialog
├── TrayIconService.cs                 # Shell_NotifyIcon tray icon
├── TargetFollowService.cs             # Manual + auto target selection
├── WindowTracker.cs                   # Win32 window enumeration + filtering
├── WindowsGraphicsCaptureController.cs# WGC capture + frame pump
├── HotkeyService.cs / Hotkey*.cs      # Global hotkey registration + capture control
├── StartupRegistration.cs            # Start-with-Windows (HKCU Run key)
├── AppSettings.cs                     # Settings model + JSON store
├── AppLog.cs                          # Logging + daily-rolling file sink
├── app.manifest                       # DPI awareness, OS compatibility
├── Package.appxmanifest               # MSIX packaging metadata (optional path)
├── Assets/                            # App/tile icons
├── Properties/
│   ├── launchSettings.json            # Debug launch profiles
│   └── PublishProfiles/               # win-x64 / win-x86 / win-arm64 publish profiles
└── docs/                              # Per-phase design + feasibility notes
```

---

## Prerequisites

- **Windows 11**, build 22000 or newer (the minimum target is `10.0.22000.0`).
- **.NET 10 SDK** (the project was last built with SDK `10.0.300`). Verify with:
  ```powershell
  dotnet --version
  ```
- **Windows App SDK** runtime — restored automatically as a NuGet package
  (`Microsoft.WindowsAppSDK`) on build; no separate installer is required for the unpackaged
  app during development.
- **Optional — Visual Studio 2022/2026** with the *.NET Desktop Development* and *Windows
  App SDK C# Templates* components, if you prefer IDE build/debug over the CLI. VS Code with
  the *C# Dev Kit* extension also works.

No admin rights are needed for the output-window-first workflow.

---

## Build

From this directory (`./CursorFollowWin/`):

```powershell
# Restore + build the default platform (x64), Debug
dotnet build CursorFollowWin.slnx -c Debug

# Release build
dotnet build CursorFollowWin.slnx -c Release

# Target a specific platform explicitly
dotnet build CursorFollowWin.csproj -c Debug -p:Platform=ARM64
```

The project picks a Runtime Identifier automatically from the platform
(`x64`→`win-x64`, `x86`→`win-x86`, `ARM64`→`win-arm64`), so a plain `dotnet build` produces a
`win-x64` Debug build by default.

Build output lands in:

```text
bin\<Configuration>\net10.0-windows10.0.26100.0\<rid>\CursorFollowWin.exe
```

> In Visual Studio, open `CursorFollowWin.slnx` and build with **Ctrl+Shift+B**.

---

## Run

Because the app is **unpackaged** (`WindowsPackageType=None`), you can run it directly:

```powershell
# Build-and-run via the SDK
dotnet run --project CursorFollowWin.csproj -c Debug

# …or launch the built executable directly
.\bin\Debug\net10.0-windows10.0.26100.0\win-x64\CursorFollowWin.exe
```

On launch the app:

1. Enforces a **single instance** (a second launch just re-activates the existing output window).
2. Loads settings, applies Start-with-Windows registration, and shows the output window.
3. Adds the **tray icon** — right-click it for the panel, show/hide output, settings, and exit.
4. Registers the global hotkeys.

To share the tracked window, point your meeting/recording app's *window share* picker at the
**"CursorFollow Output"** window.

### Hotkeys (defaults)

| Action               | Default shortcut |
| -------------------- | ---------------- |
| Toggle auto-follow   | `Ctrl+Alt+F`     |
| Toggle output window | `Ctrl+Alt+S`     |

Both are editable in the settings dialog; conflicts are reported there without failing startup.

---

## Debug

### Visual Studio

1. Open `CursorFollowWin.slnx`.
2. Pick the launch profile **`CursorFollowWin (Unpackaged)`** (the `… (Package)` profile uses
   MSIX packaging and is not the default development path).
3. Set the platform to **x64** (or your machine's architecture) and press **F5**.

Breakpoints work across the managed app, including the capture pump and tray/hotkey callbacks.
Note that some UI/tray/hotkey and screen-reader behavior can only be verified by interacting
with the running desktop app — it cannot be exercised headlessly.

### VS Code

With the C# Dev Kit installed, open this folder, select `CursorFollowWin.csproj` as the
startup project, and use **Run and Debug** (F5). Alternatively attach to a running
`CursorFollowWin.exe` via *.NET Core Attach*.

### Logs

Diagnostics are written to a daily-rolling file under:

```text
%LocalAppData%\CursorFollowWin\Logs\
```

Log lines are categorized by component — `App`, `Capture`, `Output`, `WindowTracker`,
`Hotkeys`, `Startup` — so you can trace which subsystem produced each line. Minimum level is
`Information`. Unhandled exceptions are logged before the app surfaces them.

---

## Configuration

User settings are persisted as versioned, indented JSON at:

```text
%LocalAppData%\CursorFollowWin\settings.json
```

Settings absent from an older file fall back to current defaults on load (so upgrades don't
break hotkeys, scaling, or filter lists). Notable keys:

| Key                                          | Default        | Meaning                                       |
| -------------------------------------------- | -------------- | --------------------------------------------- |
| `StartWithWindows`                           | `false`        | Register under the HKCU `Run` key             |
| `AutoShareOnLaunch`                           | `false`        | Start following a target immediately          |
| `HideWhenNotSharing`                          | `false`        | Hide the output window when idle              |
| `PinOutputOnTop`                              | `false`        | Keep the output window topmost                |
| `CaptureQuality`                              | `Balanced`     | Capture preset (buffer depth + fps cap)       |
| `OutputScaleMode`                             | `Fit`          | `Fit` / `Fill` / `Actual` output scaling      |
| `WindowFilterMode`                            | `All`          | `All` / `Include` / `Exclude`                 |
| `IncludeWindowIdentities` / `Exclude…`        | `[]`           | Identity lists for the filter modes           |
| `AutoFollowHotkey` / `ToggleOutputHotkey`     | `Ctrl+Alt+F` / `Ctrl+Alt+S` | Global hotkeys                   |

Deleting `settings.json` resets the app to defaults.

---

## Publish

Self-contained publish profiles are provided for each platform:

```powershell
dotnet publish CursorFollowWin.csproj -c Release -p:PublishProfile=win-x64
dotnet publish CursorFollowWin.csproj -c Release -p:PublishProfile=win-arm64
dotnet publish CursorFollowWin.csproj -c Release -p:PublishProfile=win-x86
```

These produce a **self-contained** build under
`bin\Release\net10.0-windows10.0.26100.0\<rid>\publish\`. Release builds enable ReadyToRun
(trimming is intentionally off — it is not safe for WinUI/XAML; see
[docs/Installer.md](docs/Installer.md)).

## Installer

A per-user MSI (no admin required) is built with WiX. From this directory:

```powershell
# Build (and optionally sign) the MSI -> installer/dist/
./scripts/package.ps1 -Rid win-x64

# Verify it installs, launches, upgrades, and uninstalls cleanly
./scripts/verify-install.ps1
```

The MSI installs to `%LocalAppData%\Programs\CursorFollowWin`, adds a Start-menu shortcut and an
Add/Remove-Programs entry, supports in-place major upgrades (preserving user settings), and on
uninstall removes the app, the `Run` value, and `%LocalAppData%\CursorFollowWin`. See
[docs/Installer.md](docs/Installer.md) for the full packaging guide and
[docs/CodeSigning.md](docs/CodeSigning.md) for the signing plan.

---

## Related docs

- [TechStack.md](TechStack.md) — stack decisions and the longer-term multi-project architecture.
- [Requirements.html](Requirements.html) — product requirements.
- [docs/Installer.md](docs/Installer.md) — WiX MSI packaging, scripts, versioning, upgrades.
- [docs/CodeSigning.md](docs/CodeSigning.md) — code-signing plan and mechanics.
- [docs/Troubleshooting.md](docs/Troubleshooting.md) — reset, capture/sharing/hotkey/elevation fixes.
- [docs/OutputWindowFeasibility.md](docs/OutputWindowFeasibility.md) — output-window approach validation.
- [docs/Phase1TrayUi.md](docs/Phase1TrayUi.md) — tray, panel, settings.
- [docs/Phase2WindowTracking.md](docs/Phase2WindowTracking.md) — enumeration, filtering, auto-follow.
- [docs/Phase3LiveOutputPipeline.md](docs/Phase3LiveOutputPipeline.md) — unified follow service + telemetry.
