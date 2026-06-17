Research the requested CursorFollow topic before making code changes.

Requirements:

1. Do not edit files yet.
2. Identify existing implementation points in `CursorFollowMac/`, `CursorFollowWin/`, `CursorFollowWinPrototype/`, shared contracts, and platform camera/output paths as applicable.
3. For Windows work, default to shareable output-window delivery first and only research virtual camera details when explicitly requested.
4. Call out API or permission constraints specific to the platform: macOS capture/camera extension behavior, or Windows Graphics Capture/output-window/protected-content behavior.
5. Provide a short risk list (latency, switching behavior, signing/entitlements, permissions, protected/elevated content).
6. End with a concrete implementation plan and expected file touches.

Reference context first:

- `@Docs/Copilot/context-cursorfollow.md`
- `@Docs/Copilot/domain-glossary.md`
