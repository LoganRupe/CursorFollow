# Code Signing Plan — CursorFollowWin

The MSI and app are shipped **unsigned today**. This document is the plan for signing them and
the exact mechanics, so signing can be turned on by supplying a certificate to `package.ps1` —
no code or installer changes required.

## Why sign

An unsigned per-user installer runs, but:

- **SmartScreen** shows a "Windows protected your PC" warning on first run from the internet
  (the file carries the Mark-of-the-Web). Users must click *More info → Run anyway*.
- The ARP entry and UAC-free install still work, but the publisher shows as **"Unknown"**.
- Some managed/enterprise environments and AV/EDR products distrust unsigned binaries outright.

Signing with a trusted certificate removes the warning (immediately for EV/Trusted Signing,
or after reputation accrues for standard OV certs) and shows a verified publisher.

## What gets signed

`package.ps1` signs, in order:

1. **`CursorFollowWin.exe`** — before it is embedded in the MSI cab, so the installed app is
   trusted.
2. **The MSI** — after the cab is built, so the download itself is trusted.

> The bundled .NET / WinUI / Win2D DLLs are already signed by Microsoft. Re-signing every
> payload DLL is optional and not done here; signing the exe + MSI is the meaningful surface.

## Certificate options (pick one)

| Option | SmartScreen reputation | Cost / effort | Notes |
| ------ | ---------------------- | ------------- | ----- |
| **Azure Trusted Signing** | Immediate | Low (cloud, ~$10/mo), Microsoft-validated identity | **Recommended.** No hardware token; signs via a cloud Key Vault. Works in CI. |
| **EV code-signing cert** | Immediate | High; hardware token (HSM/USB) | Token makes headless CI painful. |
| **OV / standard cert** | Builds over time | Medium | Reputation accrues with download volume; early users still see warnings. |
| **Self-signed** | Never (must be manually trusted) | Free | **Dev/test only.** Import into Trusted Root + Trusted Publishers to test the signed flow locally. |

The product identity is `Logan Rupe` (the MSI `Manufacturer` and the assembly `Company`); the
signing certificate's subject should match that publisher name.

## How signing runs

`package.ps1` calls `signtool.exe` (from the Windows SDK; it is auto-located under
`C:\Program Files (x86)\Windows Kits\10\bin\*\x64\`) with SHA-256 and an RFC-3161 timestamp:

```text
signtool sign /fd SHA256 /tr <TimestampUrl> /td SHA256 [/sha1 <thumbprint> | /f <pfx> /p <pwd>] <file>
```

**Timestamping is required** (`/tr` + `/td`): it lets signatures remain valid after the
certificate expires. The default timestamp server is `http://timestamp.digicert.com`
(override with `-TimestampUrl`).

### Local signing with a PFX

```powershell
./scripts/package.ps1 -Rid win-x64 `
  -CertPath C:\secure\cursorfollow-codesign.pfx `
  -CertPassword (Read-Host -AsSecureString | ConvertFrom-SecureString -AsPlainText)
```

### Local signing with a cert already in the user store

```powershell
./scripts/package.ps1 -Rid win-x64 -CertThumbprint <SHA1-THUMBPRINT>
```

Without `-CertPath`/`-CertThumbprint`, `package.ps1` builds successfully and prints an
**"output is UNSIGNED"** notice.

## Azure Trusted Signing (recommended target)

When moving to Trusted Signing, the only change is *how* signtool is invoked (it uses the
Trusted Signing dlib + an account/profile instead of `/sha1`/`/f`). The two call sites in
`package.ps1` (`Invoke-Sign`) are the single place to adapt. Steps:

1. Create a **Trusted Signing account** + **certificate profile** in Azure; complete identity
   validation for the `Logan Rupe` publisher.
2. Grant the CI principal the *Trusted Signing Certificate Profile Signer* role.
3. Install the Trusted Signing dlib and call
   `signtool sign /v /fd SHA256 /tr <ts> /td SHA256 /dlib <Azure.CodeSigning.Dlib.dll> /dmdf <metadata.json> <file>`.
4. Store the Azure credentials as CI secrets (never in the repo).

## CI / release checklist

- [ ] Certificate (or Trusted Signing profile) provisioned for publisher `Logan Rupe`.
- [ ] Signing secrets stored in the CI secret store, not in source.
- [ ] `package.ps1` invoked with the cert; build log shows **"Signing CursorFollowWin.exe"**
      and **"Signing …​.msi"** (no UNSIGNED notice).
- [ ] Verify after build: `signtool verify /pa /all installer\dist\*.msi`.
- [ ] Smoke-test the signed MSI on a clean VM: no SmartScreen "Unknown publisher".
