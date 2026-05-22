# Git Workflow

## Branching

Recommended branch naming:

- `feature/{scope}/{description}`
- `fix/{scope}/{description}`
- `chore/{scope}/{description}`

Examples:

- `feature/capture/window-switch-debounce`
- `fix/window-tracker/cursor-hit-test-order`
- `chore/docs/permissions-setup`

## Safety Rules

1. Do not implement directly on `main`/`master` without explicit approval.
2. Keep commits scoped to one concern when possible.
3. If signing or entitlements are changed, mention it clearly in commit body.

## Version Bump Pattern

macOS system extensions are identified by bundle version. The system will only
replace a running extension if the new build has a **higher** version number.

### Rules

- Bump `CURRENT_PROJECT_VERSION` (build number) on the **CameraExtension** target
  for every deployment that needs the extension to reload.
- Bump `MARKETING_VERSION` (minor) for user-visible feature changes.
- The **host app** version is independent; only bump when shipping host-side changes.

### Where to edit

In `CursorFollowHost.xcodeproj/project.pbxproj`, update both the **Debug** and
**Release** build configurations for the CameraExtension target:

```
5902C7852FBD97F300FFEA1C /* Debug */   → CURRENT_PROJECT_VERSION = <next>;
5902C7862FBD97F300FFEA1C /* Release */ → CURRENT_PROJECT_VERSION = <next>;
```

### Deploy sequence

```bash
cd CursorFollowHost
xcodebuild -project CursorFollowHost.xcodeproj -scheme CursorFollowHost -configuration Debug build
killall CursorFollowHost 2>/dev/null; sleep 1
rm -rf /Applications/CursorFollowHost.app
cp -R ~/Library/Developer/Xcode/DerivedData/CursorFollowHost-*/Build/Products/Debug/CursorFollowHost.app /Applications/
open /Applications/CursorFollowHost.app
# Verify:
systemextensionsctl list 2>&1 | grep loganrupe
```

### Current version

- CameraExtension: `MARKETING_VERSION = 1.1`, `CURRENT_PROJECT_VERSION = 6`
- Host app: `MARKETING_VERSION = 1.0`, `CURRENT_PROJECT_VERSION = 1`

## PR Checklist

- [ ] Summary includes user-visible behavior change
- [ ] Risks and edge cases documented
- [ ] Build validation included
- [ ] Docs updated when architecture changes
