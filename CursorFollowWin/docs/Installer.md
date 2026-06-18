# Packaging — WiX MSI Installer

CursorFollowWin ships as a **per-user MSI** built with the [WiX Toolset](https://wixtoolset.org/)
v5. Per-user means it installs **without elevation (no UAC)**, matching the app's "no admin
rights" design: files land under `%LocalAppData%\Programs\CursorFollowWin`, and the Start-menu
shortcut and Add/Remove-Programs entry are per-user.

## Prerequisites

- **.NET 10 SDK** (build + publish).
- **WiX 5** — restored automatically as the `WixToolset.Sdk` MSBuild SDK referenced by
  `installer/CursorFollowWin.Installer.wixproj`; no separate global install is required to build
  the MSI. (The `wix` global tool is only needed for ad-hoc CLI use.)
- **Windows SDK** (only if signing — provides `signtool.exe`).

## One command

```powershell
./scripts/package.ps1 -Rid win-x64
```

This publishes the self-contained app, reads the version from the built exe, builds the MSI, and
stages it at `installer/dist/CursorFollowWin-<version>-<rid>.msi`. Use `-Rid win-arm64` or
`-Rid win-x86` for the other architectures. To sign, pass a certificate — see
[CodeSigning.md](CodeSigning.md).

## What the installer does

| Aspect | Behavior |
| ------ | -------- |
| **Scope** | Per-user (no elevation). Install dir: `%LocalAppData%\Programs\CursorFollowWin`. |
| **Payload** | The entire self-contained publish folder, harvested at build time (WiX `Files`). |
| **Shortcut** | Start-menu shortcut **"CursorFollow"** → installed exe, with the app icon. |
| **ARP** | Add/Remove-Programs entry (publisher *Logan Rupe*, version, icon, help/about links). |
| **Upgrade** | `MajorUpgrade` replaces an existing install in place; downgrades are blocked. **User settings are preserved across upgrades.** |
| **Uninstall** | Removes the install folder, the shortcut, the HKCU `Run` value, and `%LocalAppData%\CursorFollowWin` (settings + logs). |

The cleanup of the `Run` value and the data folder runs only on a **true uninstall**
(`REMOVE=ALL AND NOT UPGRADINGPRODUCTCODE`) via deferred, impersonated actions, so an upgrade
never wipes user data.

## Versioning

The product version has a **single source of truth**: `<Version>` in `CursorFollowWin.csproj`.
The exe is stamped with it, the About dialog reads it, and `package.ps1` reads the exe's
`FileVersion` and passes it to WiX. **To release a new version, bump `<Version>` and re-run
`package.ps1`** — a major upgrade falls out automatically.

> The `UpgradeCode` GUID in `installer/Package.wxs` is the stable product identity across all
> versions. **Never change it** — doing so breaks the upgrade chain (the new MSI would install
> side-by-side instead of upgrading).

## Verifying a build

`scripts/verify-install.ps1` drives the MSI through its whole lifecycle on the current machine —
install → assert files/shortcut/registry/ARP → smoke-launch (waits for "Startup complete") →
uninstall → assert full cleanup (including the planted `Run` sentinel) — and exits non-zero on any
failed check. Run it after `package.ps1`:

```powershell
./scripts/package.ps1 -Rid win-x64
./scripts/verify-install.ps1
```

## Scripts

| Script | Purpose |
| ------ | ------- |
| `scripts/build.ps1` | Restore, build the solution, run the xUnit tests. |
| `scripts/publish.ps1` | Self-contained ReadyToRun publish for one RID; returns the publish path. |
| `scripts/package.ps1` | Publish → read version → build (optionally sign) the MSI into `dist/`. |
| `scripts/verify-install.ps1` | Full install/uninstall/cleanup verification of an MSI. |

## Notes & gotchas

- **Trimming is disabled** (`PublishTrimmed=False`). WinUI/XAML/Win2D resolve types via
  reflection and XAML metadata that the IL trimmer cannot see; trimming produces a build that
  crashes at runtime. ReadyToRun is kept for startup speed. The payload is ~166 MB (≈48 MB MSI).
- **WinUI publish PRI fix.** A post-publish target (`_CopyAppPriToPublish` in the csproj) copies
  the app's root `CursorFollowWin.pri` into the publish folder. Without it, `dotnet publish` drops
  the root PRI and the app throws `XamlParseException` locating `MainWindow.xaml` from the Output
  assembly. `publish.ps1` asserts the PRI is present as a guard.
- **Always-rebuild MSI.** `package.ps1` builds the WiX project with `-t:Rebuild` because the WiX
  SDK's incremental check does not track the `Version`/`PublishDir` properties and would otherwise
  ship a stale MSI after a version bump.
