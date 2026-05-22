# CursorFollow Documentation

Project docs for CursorFollow — a macOS menu bar app that tracks a target window and exposes the capture as a virtual camera via a CoreMediaIO camera extension.

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
└── CameraExtensionV2/    # Active implementation plan
    ├── _session.md
    ├── Requirements.md
    └── Plan.md
```

## Current Status

Rebuilding from scratch. See `CameraExtensionV2/` for the active plan.

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

- Camera extension must use PlugInKit (`com.apple.cmio.registerassistantservice`), NOT ExtensionKit
- Screen Recording and Accessibility permissions
- Code signing and entitlements for extension discovery
- Window switching edge cases (full-screen, Spaces, minimized windows)
- Frame latency across IPC boundary
