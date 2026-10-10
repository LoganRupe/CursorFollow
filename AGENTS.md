# AGENTS.md

Guidance for AI coding agents (Claude Code, Codex, Copilot, Cursor) working in this repo.
Human contributors: the same rules apply.

## What this is

CursorFollow captures a target window and renders it into one stable window named
**CursorFollow Output**, which users share from a meeting app's window picker. It follows
the target as focus changes. Three independent native apps, no shared code:

| Dir | Platform | Stack | Capture |
| --- | --- | --- | --- |
| `CursorFollowMac/` | macOS 26.4+ | Swift, SwiftUI + AppKit, Xcode project | ScreenCaptureKit |
| `CursorFollowWin/` | Windows 11 | C#, WinUI 3, .NET 10 | Windows Graphics Capture + D3D11 |
| `CursorFollowLinux/` | Hyprland (Wayland) | C++20, GTK 4, GNU make | `hyprland-toplevel-export-v1` |

The shared output window is the product. There is no virtual camera; the old macOS
CoreMediaIO extension was removed, so don't reintroduce one unless asked.

Behaviour should match across platforms: Target Mode (Auto/Manual), filter mode
(All/Include/Exclude), output scaling (Fit/Fill/Actual), Pause/Resume, Show/Hide.
When you change one of these on one platform, say whether the others need the same change.

## Build and test

Run the checks for every platform you touched. Each app builds only on its own OS.

```bash
# macOS (no Apple account needed; Debug builds are ad-hoc signed)
cd CursorFollowMac
xcodebuild -project CursorFollowMac.xcodeproj -scheme CursorFollowMac \
  -destination 'platform=macOS' -only-testing:CursorFollowMacTests test

# Linux (needs gtk4, json-glib, wayland-client, wayland-scanner)
cd CursorFollowLinux && make -j"$(nproc)" && make test
```

```powershell
# Windows
cd CursorFollowWin
dotnet build CursorFollowWin.slnx -c Debug
dotnet test tests/CursorFollowWin.Tests
```

Releases: `CursorFollowMac/scripts/package.sh` and `CursorFollowWin/scripts/package.ps1`.
macOS releases are self-signed and not notarized on purpose; see
`Docs/Distribution/Packaging.md` before touching signing.

## Things that have bitten us

- **Capture is hot-path code.** Frames arrive at up to 60 fps. Never publish per-frame
  state into SwiftUI (`@Published`), XAML bindings or GTK widgets; a per-frame
  `@Published` counter once caused a full relayout every frame and pegged the CPU.
  Keep counters off the UI and sample them on a timer.
- **Don't capture our own output window.** Every platform filters it out of the
  target list. Keep that filter when changing window enumeration.
- **macOS Screen Recording permission** is tied to the code signature. Ad-hoc signed
  Debug builds lose the grant on every rebuild; that's expected, not a bug.
- **Identifiers** are `io.github.loganrupe.*` (bundle ID, Linux app id, logger
  subsystems). Changing one resets user settings and permissions; don't.
- Edge cases worth a test or a note: minimized windows, full-screen apps and Spaces
  (macOS), elevated or protected windows (Windows), workspaces and special workspaces
  (Hyprland).

## Conventions

- Match the surrounding code's style, naming and comment density.
- Branches: `feature|fix|chore/{scope}/{description}`, e.g. `fix/win-capture/black-frame-on-resize`.
- Commits: Conventional Commits with a platform scope, e.g. `fix(mac/capture): ...`,
  `feat(win/tray): ...`, `feat(linux): ...`. One concern per commit.
- If you change signing, entitlements or identifiers, call it out in the commit body.
- Add user-visible changes to `CHANGELOG.md` under **Unreleased**.
- Platform READMEs are user-facing docs; keep them current when behaviour changes.
