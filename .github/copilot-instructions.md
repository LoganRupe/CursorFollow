# Copilot Instructions — CursorFollow

## Overview

CursorFollow is a macOS menu bar utility that tracks a target window and exposes the result as a virtual camera feed.

## Core Domains

- Host app UI/state in `CursorFollow/`
- Capture and target switching (`WindowTracker`, `CaptureEngine`)
- Shared contracts in `Shared/`
- Camera extension implementation in `CameraExtension/`

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
5. Note edge cases explicitly (minimized windows, full-screen apps, Spaces).
