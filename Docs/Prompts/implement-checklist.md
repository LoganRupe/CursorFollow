Use this checklist before and during implementation.

## Pre-Implementation

- [ ] Confirm target branch is not protected (`main`/`master`) unless explicitly intended.
- [ ] Confirm whether task is research-only or code-change.
- [ ] Review `@Docs/Copilot/context-cursorfollow.md`.
- [ ] Identify permission/signing implications.
- [ ] For Windows work, confirm whether the delivery target is the shareable output window or the optional virtual camera path.

## During Implementation

- [ ] Preserve low-latency defaults (queue depth, frame pacing).
- [ ] Avoid introducing capture feedback loops (capturing conferencing app previews).
- [ ] Keep CursorFollow's own output window excluded from auto-follow by default.
- [ ] Handle no-target and unavailable-target states gracefully.
- [ ] Keep window switching behavior deterministic.

## Validation

- [ ] Build succeeds.
- [ ] Start/stop path works.
- [ ] Follow mode switch works.
- [ ] Exclude list honored.
- [ ] Error reporting is actionable.

## Output Window Path (primary for Windows)

- [ ] Output window preserves captured aspect ratio and remains shareable in meeting-app window pickers.
- [ ] Users can keep their real webcam selected while sharing the CursorFollow output window.
- [ ] Hide/show, pin-on-top, resize, and no-target states behave predictably.

## Camera Extension / Virtual Camera Path (when touched)

- [ ] CMIO provider/device/stream contract still valid.
- [ ] Host-extension transport contract unchanged or documented.
- [ ] Signing and entitlements requirements documented in PR notes.
- [ ] Windows virtual camera COM/Media Foundation registration is documented separately when in scope.
