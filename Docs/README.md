# CursorFollow Documentation

Project docs for CursorFollow — a macOS menu bar app that tracks a target window and presents the capture in a stable, shareable output window.

## Structure

```
Docs/
├── README.md
├── Copilot/              # AI assistant context
│   ├── context-cursorfollow.md
│   ├── domain-glossary.md
│   └── git-workflow.md
├── Prompts/              # Reusable prompt templates
│   ├── _session-template.md
│   ├── feature-plan.md
│   ├── feature-research.md
│   └── implement-checklist.md
├── CameraExtensionV2/    # Historical virtual camera plan
    ├── _session.md
    ├── Requirements.md
    └── Plan.md
└── SharedWindowV1/       # Active shared-window product plan
    ├── index.html
    ├── requirements.html
    └── plan.html
```

## Current Status

Pivoting from virtual-camera output to a normal macOS output window that users can select from conferencing screen-share pickers. See `SharedWindowV1/index.html` for the active plan.

`CameraExtensionV2/` remains as historical reference for the CoreMediaIO virtual camera approach.

## Feature Documentation Pattern

For each substantial feature, create:

```
Docs/{FeatureName}/
├── _session.md
├── Requirements.md
└── Plan.md
```

Use `Prompts/_session-template.md` as the starting point.

## High-Risk Areas

- Screen Recording and Accessibility permissions
- Output window visibility and share-picker discoverability
- Avoiding recursive capture of CursorFollow's own output window
- Window switching edge cases (full-screen, Spaces, minimized windows)
- Frame latency from ScreenCaptureKit callback to visible output
