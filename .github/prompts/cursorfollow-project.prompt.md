---
description: "Plan or implement a CursorFollow feature with architecture-aware constraints"
mode: "agent"
---

#file:Docs/Copilot/context-cursorfollow.md
#file:Docs/Copilot/domain-glossary.md
#file:Docs/Prompts/implement-checklist.md

Work on the user's CursorFollow request.

Requirements:

1. Start with brief research of existing project files before editing.
2. Keep latency, frame stability, and share-window ergonomics visible in decisions.
3. For Windows work, prefer shareable output-window delivery first so users can keep their real webcam active; treat virtual camera work as optional/later unless the user explicitly asks for it.
4. Call out permissions/signing implications if the change touches capture, extension, camera, installer, or Windows protected/elevated window paths.
5. Implement the smallest safe change set first.
6. Validate build after changes and summarize outcomes.
