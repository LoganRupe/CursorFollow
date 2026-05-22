Use this checklist before and during implementation.

## Pre-Implementation

- [ ] Confirm target branch is not protected (`main`/`master`) unless explicitly intended.
- [ ] Confirm whether task is research-only or code-change.
- [ ] Review `@Docs/Copilot/context-cursorfollow.md`.
- [ ] Identify permission/signing implications.

## During Implementation

- [ ] Preserve low-latency defaults (queue depth, frame pacing).
- [ ] Avoid introducing capture feedback loops (capturing conferencing app previews).
- [ ] Handle no-target and unavailable-target states gracefully.
- [ ] Keep window switching behavior deterministic.

## Validation

- [ ] Build succeeds.
- [ ] Start/stop path works.
- [ ] Follow mode switch works.
- [ ] Exclude list honored.
- [ ] Error reporting is actionable.

## Camera Extension Path (when touched)

- [ ] CMIO provider/device/stream contract still valid.
- [ ] Host-extension transport contract unchanged or documented.
- [ ] Signing and entitlements requirements documented in PR notes.
