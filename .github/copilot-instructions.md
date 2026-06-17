# Copilot Instructions — CursorFollow

## Overview

CursorFollow tracks a target window and publishes the result through the platform-appropriate sharing path.

- macOS currently exposes the capture as a CoreMediaIO virtual camera and also has a shareable output window.
- Windows should prioritize a shareable output window first, so users can keep their real webcam active while sharing CursorFollow's tracked window in meeting apps. Treat Windows virtual camera work as optional/later unless explicitly requested.

## Core Domains

- Host app UI/state in `CursorFollowMac/` and future `CursorFollowWin/`
- Capture and target switching (`WindowTracker`, `CaptureEngine` or platform equivalents)
- Shareable output window rendering and presentation behavior
- Shared contracts and diagnostics
- macOS camera extension implementation in `CameraExtension/`
- Windows virtual camera research/prototype only when specifically in scope

## Branch Safety

Before making code changes:

1. Check current branch name.
2. If on `main` or `master`, request confirmation before proceeding.
3. Prefer branch names:
   - `feature/{scope}/{description}`
   - `fix/{scope}/{description}`

## Context Files

- `@Docs/Copilot/context-cursorfollow.md`
- `@Docs/Copilot/domain-glossary.md`
- `@Docs/Copilot/git-workflow.md`

## Session Tracking

For larger changes, maintain:

- `Docs/{FeatureName}/_session.md`
- `Docs/{FeatureName}/Requirements.md`
- `Docs/{FeatureName}/Plan.md`

Use `@Docs/Prompts/_session-template.md` to start.

## Engineering Guidelines

1. Prioritize low latency and frame stability.
2. Treat permission and signing constraints as first-class requirements.
3. Prefer existing code patterns over introducing new abstractions unless justified.
4. Keep extension-facing interfaces stable and documented.
5. Note edge cases explicitly (minimized windows, full-screen apps, Spaces, protected/elevated Windows content).
