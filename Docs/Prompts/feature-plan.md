Plan a CursorFollow feature using these outputs.

Inputs:

- Feature name
- User-facing behavior
- Latency/performance expectations
- Compatibility constraints (meeting-app window sharing first on Windows; camera behavior only when explicitly in scope)

Output format:

1. `Requirements.md` with acceptance criteria
2. `Plan.md` with architecture decisions
3. `_session.md` from template for execution tracking

Planning requirements:

- List affected files
- Include testing/validation approach
- Include rollback plan for risky changes
- Explicitly note signing/permissions impacts when relevant
- For Windows features, plan around a shareable output window first so the user's real webcam can remain active during calls. Treat virtual camera output as a separate optional track unless requested.

Reference:

- `@Docs/Copilot/context-cursorfollow.md`
- `@Docs/Prompts/_session-template.md`
