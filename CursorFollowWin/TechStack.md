# CursorFollowWin Tech Stack Plan

## Recommendation

Build CursorFollowWin as a Windows 11 desktop product centered on C# and .NET 10 LTS, with WinUI 3 for the user-facing tray app and shareable output window.

The maintainable shape should mirror the product workflow rather than the macOS virtual-camera implementation detail: host UI and state, window tracking, capture, output-window rendering, and optional camera output are separate projects with explicit contracts. The Phase 0 gate is now a usable shareable output window, because the core Windows workflow is keeping the user's real webcam active while sharing CursorFollow's tracked-window surface.

## Version Baseline

| Area         | Choice                                  | Reason                                                                                                                                            |
| ------------ | --------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Runtime      | .NET 10 LTS                             | Current LTS in 2026 with support through November 2028. Avoid starting on .NET 8 because it is already near end of support.                       |
| Language     | C# latest supported by .NET 10          | Lets the app use current compiler/runtime improvements while staying on an LTS runtime.                                                           |
| Target OS    | Windows 11, build 22000+                | Matches product scope and the modern Windows Graphics Capture baseline.                                                                           |
| Architecture | x64 first, arm64 later if needed        | Capture, rendering, and conferencing-window-sharing behavior should be proven on x64 before broadening.                                           |
| Deployment   | Unpackaged WinUI 3 app installed by WiX | Gives direct control over startup, logs, capture permissions, and uninstall cleanup. MSIX can be revisited after the output-window app is proven. |

## Project Layout

```text
CursorFollowWin/
├── CursorFollowWin.slnx
├── src/
│   ├── CursorFollowWin.App/          # WinUI 3 tray host, panel, settings, output window
│   ├── CursorFollowWin.Capture/      # Window enumeration, tracking, filtering, WGC capture
│   ├── CursorFollowWin.Output/       # Output-window rendering, overlays, sizing, share behavior
│   ├── CursorFollowWin.Camera/       # Optional later camera control and registration facade
│   ├── CursorFollowWin.Camera.Native/# Optional native MF custom media source if required
│   └── CursorFollowWin.Shared/       # Contracts, settings models, diagnostics, frame metadata
├── tests/
│   ├── CursorFollowWin.Capture.Tests/
│   ├── CursorFollowWin.Shared.Tests/
│   └── CursorFollowWin.Integration.Tests/
├── installer/
│   └── CursorFollowWin.Installer/    # WiX package and cleanup actions
└── docs/
    ├── OutputWindowFeasibility.md
    ├── Build.md
    ├── Verify.md
    └── Troubleshooting.md
```

Use `.slnx` if the installed .NET SDK and IDE support it cleanly; otherwise use a conventional `.sln` initially and migrate later. Maintainability beats novelty here.

## UI Stack

Use WinUI 3 through the stable Windows App SDK channel.

Why:

- Best alignment with Windows 11 visuals, accessibility, DPI behavior, and Fluent controls.
- C#/.NET first-class experience without carrying legacy WPF styling work.
- Works with Win32 interop needed for tray icon placement, window handles, capture, and hotkeys.

Implementation notes:

- Use a regular WinUI 3 desktop window for settings and the primary shareable output surface.
- Use a custom Win32 `Shell_NotifyIcon` wrapper generated with CsWin32 for the tray icon instead of depending on a broad third-party tray library.
- Position the compact panel near the taskbar notification area using Win32 monitor/work-area APIs.
- Keep UI state in view models and service interfaces so tracking/capture behavior can be tested without XAML.

Avoid for the first version:

- .NET MAUI: tray and low-latency capture/rendering desktop integration are not the sweet spot.
- WPF: mature and viable, but it would need more styling work to feel like a polished Windows 11 app.
- Avalonia: strong cross-platform option, but this product is intentionally Windows-native and needs deep Win32, Windows Graphics Capture, Direct3D, and meeting-app sharing behavior.

## Native Interop Policy

Use C# for the app and product logic. Use native code only at OS boundaries where it materially improves reliability.

Recommended interop tools:

- CsWin32 for Win32 and COM declarations used from C#.
- Vortice.Windows for Direct3D 11, DXGI, and related graphics interop from managed code.
- Media Foundation and native C++ only for an optional future virtual-camera mode.

Avoid SharpDX because it is no longer maintained.

## Window Tracking

Use Win32 as the primary source of truth:

- `EnumWindows` for visible top-level windows.
- `GetForegroundWindow` for active-window auto-follow.
- `WindowFromPoint` / `ChildWindowFromPointEx` for cursor-under-window follow where useful.
- `GetWindowThreadProcessId`, `OpenProcess`, and `QueryFullProcessImageName` for process identity.
- `DwmGetWindowAttribute` for cloaked, bounds, and thumbnail-related state.

Use UI Automation only as an enrichment layer for accessibility names or packaged app metadata when Win32 identity is insufficient. Keep UIA out of the hot path.

## Capture Pipeline

Use Windows Graphics Capture with Direct3D 11:

- Create capture items from HWND through `IGraphicsCaptureItemInterop` for auto-follow and manual selection.
- Use `Direct3D11CaptureFramePool` with `B8G8R8A8UIntNormalized` for the initial SDR path.
- Keep frame buffers shallow, starting with 2 or 3 buffers to match the macOS latency posture.
- Recreate the frame pool on resize or device loss.
- Include cursor by default if the active Windows API path supports it for the capture session.

Output rendering options:

- Prefer Win2D or a Direct3D-backed WinUI surface for straightforward output-window rendering.
- Preserve aspect ratio, resize cleanly, support pin-on-top, and ensure the output window is discoverable in meeting-app window sharing pickers.
- Keep a clean frame contract so optional future camera transport can be added without reshaping capture.

## Output Window Strategy

Phase 0 should validate the shareable output window first:

- Create a tray-hosted app that renders generated frames into a normal output window.
- Verify that Teams, Zoom, Slack, Google Meet/Chrome, Edge, and OBS can share the output window while the user's real webcam remains selected.
- Then replace generated frames with Windows Graphics Capture from a selected target window.
- Confirm behavior for resize, minimize, pin-on-top, hide/show, and exclusion from CursorFollow's own auto-follow list.

Preferred production shape:

- C# app controls tray state, window tracking, capture, settings, and output-window lifetime.
- Output renderer owns scaling, overlays, frame pacing, and visible fallback states.
- Frame transport passes latest frame metadata and texture/shared-memory references between capture and output rendering.

Optional virtual-camera track:

- Revisit `MFCreateVirtualCamera` / `IMFVirtualCamera` only if camera-source workflows become a product requirement.
- If pursued, treat Media Foundation, COM registration, signing, and installer cleanup as a separate compatibility project.
- DirectShow or OBS virtual camera interop remain fallback investigations, not first-version dependencies.

## Frame Transport

Prove this in two steps:

1. CPU BGRA ring buffer in shared memory or memory-mapped file. This is simpler, debuggable, and good enough for an early compatibility test.
2. D3D11 shared texture with keyed synchronization if CPU copy misses latency or CPU targets.

Keep the transport contract small:

- Output-window dimensions track the captured content aspect ratio, with sensible defaults such as 960x540 for generated/test output.
- Sequence number.
- Timestamp from `QueryPerformanceCounter` or equivalent monotonic clock.
- Pixel format.
- Frame state: live, idle, target missing, protected content, or error.

## Settings, Startup, and Hotkeys

- Persist user settings as versioned JSON under `%LocalAppData%\CursorFollowWin` using `System.Text.Json` source generation.
- Use `Microsoft.Extensions.Options` style models inside the app, even though this is a desktop product.
- Register startup through the normal Windows startup app path appropriate for the chosen installer model.
- Register global hotkeys with Win32 `RegisterHotKey`; report conflicts in settings without failing app startup.

## Diagnostics

Use `Microsoft.Extensions.Logging` throughout all managed projects.

Recommended sinks:

- Rolling local log file under `%LocalAppData%\CursorFollowWin\Logs`.
- Windows Event Log only for installer and fatal startup failures if useful.
- Optional ETW/EventSource later for performance tracing.

Log categories should match the architecture: `App`, `WindowTracker`, `Capture`, `Output`, `FrameTransport`, `Installer`, and `Hotkeys`. Add `Camera` only when optional virtual camera work is in scope.

## Testing

- Use xUnit for shared, tracking, filtering, settings, and non-UI behavior.
- Keep Win32 API access behind interfaces so tests can use fake window inventories and foreground-window events.
- Add integration tests for window enumeration and capture only where they can be made reliable on a Windows 11 developer machine.
- Treat meeting-app output-window sharing verification as a documented manual/compatibility matrix until automation is worth the cost.

## Installer

Use WiX Toolset for the first serious installer.

Installer responsibilities:

- Install the app.
- Add/remove startup registration.
- Clean up settings/logs according to uninstall options.
- Provide repair/reset actions for development and support.

Document admin requirements early. The output-window-first path should avoid camera registration and admin requirements unless a later installer choice introduces them.

## Open Decisions

1. Which output-window rendering path gives the best balance of low latency, crisp scaling, resize behavior, and meeting-app share compatibility?
2. Should the first output window be a pure WinUI/Win2D surface or a Direct3D-backed surface?
3. Is CPU shared memory good enough for 1080p60 on the target development machine, or is D3D11 texture sharing required immediately?
4. Should optional virtual camera support remain a separate post-MVP project?
5. Is `.slnx` supported well enough by the dev environment, or should the initial skeleton use `.sln`?

## Proposed Phase 0 Deliverable

Create the smallest possible vertical slice before building the full UI:

- .NET 10 solution with a minimal WinUI host.
- Shareable output window that displays generated color-bar/test-pattern frames.
- Manual target selection and Windows Graphics Capture once the output window is shareable.
- Compatibility matrix covering Teams, Zoom, Slack, Google Meet/Chrome, Edge, and OBS window sharing while a real webcam remains selected.
- Short decision record confirming rendering path, capture path, output-window behavior, and installer implications.
