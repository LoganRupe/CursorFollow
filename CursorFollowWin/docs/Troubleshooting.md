# CursorFollowWin — Troubleshooting & Reset

Practical fixes for the most common issues, plus how to reset the app. When in doubt, the logs
tell you what happened — see [Diagnostics](#diagnostics-logs) at the bottom.

All per-user state lives in two places:

| What | Path |
| ---- | ---- |
| Installed app | `%LocalAppData%\Programs\CursorFollowWin\` |
| Settings + logs | `%LocalAppData%\CursorFollowWin\` (`settings.json`, `Logs\`) |
| Start-with-Windows | `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` → value `CursorFollowWin` |

---

## Reset to defaults

The app self-heals from missing settings: any key absent from `settings.json` falls back to its
current default on load. So a reset is just deleting the file.

```powershell
# Close the app from the tray first, then:
Remove-Item "$env:LOCALAPPDATA\CursorFollowWin\settings.json" -ErrorAction SilentlyContinue
```

Re-launch the app to regenerate a fresh, default `settings.json`. To also clear logs, delete the
whole folder: `Remove-Item "$env:LOCALAPPDATA\CursorFollowWin" -Recurse`.

> A clean **uninstall** removes both the install folder and `%LocalAppData%\CursorFollowWin`
> automatically. A **major upgrade** preserves your settings.

---

## Capture problems

### The output window is black / shows nothing

- **Protected (DRM) content.** Windows Graphics Capture renders a black frame for windows that
  opt into display protection (some DRM video players, certain banking/secure apps). This is by
  design and cannot be bypassed. Track a different window.
- **Nothing is being tracked.** Open the tray panel and confirm a target is selected (or that
  auto-follow is on). When idle, the output window shows its placeholder, not live pixels.
- **The tracked window was minimized or closed.** WGC stops producing frames; pick another
  window or restore the original.

### "Programmatic window capture was not allowed"

The app first tries to capture automatically (programmatic access). If Windows blocks that for
the session, **use "Select target" in the panel** to pick the window via the system picker
instead — that path is always permitted. The condition is logged under the `Capture` category.

### A specific window won't capture, but others do

That window is most likely **elevated** (running as Administrator) — see below.

---

## Protected & elevated windows

Windows **UIPI** (User Interface Privilege Isolation) prevents a normally-running app from
reading or interacting with windows owned by a **higher-integrity (elevated) process**. Effects:

- An elevated window (e.g. an admin PowerShell, Task Manager, some installers) may **not appear**
  in the tracker's window list, or may fail to capture.
- Auto-follow will **skip** elevated windows and fall back to the next eligible foreground window.

**Options:**

1. Track a non-elevated window instead (recommended — the app is designed to run without admin).
2. If you genuinely must capture an elevated window, run CursorFollowWin elevated too (right-click
   → *Run as administrator*). Note that elevation is **not** required for the normal
   output-window-sharing workflow and is discouraged.

> Protected (DRM) content stays black even when elevated — UIPI and display protection are
> separate mechanisms.

---

## Output-window sharing (meeting/recording apps)

The shareable window is titled **"CursorFollow Output"**. To share it, open your meeting or
recording app's **window-share picker** and select that window. Keep your real webcam selected;
this window is shared *in addition to* the camera.

### "CursorFollow Output" doesn't appear in the share picker

- **The window is hidden.** If *Hide when not sharing* is on and nothing is being tracked, the
  window is hidden and won't enumerate. Start tracking a target, or turn that setting off, or use
  the tray → *Show output*.
- **The picker only lists monitors/specific apps.** Some apps' "window" pickers exclude certain
  windows; choose the *window* (not *screen*) mode and refresh the picker.
- **Pinned/topmost confusion.** *Pin on top* and *Hide when not sharing* are mutually exclusive;
  if one looks disabled in Settings, that's why.

### The shared view is the wrong size / cropped

Adjust **Output scaling** in Settings: *Fit* (letterbox, no crop), *Fill* (crop to fill), or
*Actual* (1:1 pixels). This changes how the tracked window is fit into the output surface.

---

## Hotkey conflicts

Global hotkeys are registered with `RegisterHotKey`. If another app already owns a combination,
Windows refuses it and **the app keeps running** — only that one hotkey is inactive.

- Settings surfaces the conflict as **"In use by another app: …"** next to the binding.
- The `Hotkeys` log category records `Failed to register hotkey … already in use.`

**Fix:** open Settings and **rebind** the conflicting action to a free combination (defaults are
`Ctrl+Alt+F` for auto-follow and `Ctrl+Alt+S` for the output window). The new binding is
persisted and re-registered immediately.

---

## Start-with-Windows didn't take effect

Registration writes the `CursorFollowWin` value under the HKCU `Run` key and is **best-effort**:
a failure is logged (`Startup` category) but never blocks launch. To inspect or fix manually:

```powershell
# View
Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name CursorFollowWin
# Remove (then re-toggle "Start with Windows" in Settings to rewrite it to the current exe path)
Remove-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name CursorFollowWin -ErrorAction SilentlyContinue
```

Re-enabling the toggle rewrites the value to the **current** executable path, so a moved or
reinstalled binary self-heals.

---

## Install / uninstall

- **Install requires no admin** — it is a per-user MSI installing under `%LocalAppData%`.
- **"A newer version is already installed"** on install means you are trying to install an
  **older** version over a newer one. Uninstall the newer one first, or install a newer build.
- **Clean reinstall:** uninstall from *Settings → Apps* (or `msiexec /x <msi>`), then reinstall.
  Uninstall removes the app, the Start-menu shortcut, the `Run` value, and
  `%LocalAppData%\CursorFollowWin`.
- The verification harness `scripts/verify-install.ps1` exercises this whole lifecycle and is the
  fastest way to confirm a build installs and cleans up correctly.

---

## Diagnostics (logs)

Daily-rolling logs are written to:

```text
%LocalAppData%\CursorFollowWin\Logs\cursorfollowwin-YYYYMMDD.log
```

Lines are tagged by component — `App`, `Capture`, `Output`, `WindowTracker`, `Hotkeys`,
`Startup`. Raise verbosity in **Settings → Logging → Log level** (None / Errors only / Standard /
Verbose) and use **Open log file** to jump to today's log. Unhandled exceptions are logged before
the app surfaces them, so the tail of the log is the first place to look after a crash.
