# Skill: Camera Extension Planning

## Description

Use this skill when planning or reviewing changes that affect the CoreMediaIO Camera Extension pathway.

## When to Use

- User asks to make virtual camera visible in conferencing apps
- Host/extension frame transport is being changed
- Entitlements/signing/package setup is part of the task

## Inputs to Gather

- Current host capture path (`CaptureEngine` behavior)
- Frame transport mechanism and constraints
- Current extension target structure and bundle setup
- Required permissions/entitlements

## Expected Output

1. Concrete implementation steps with file-level scope
2. Risks and fallback/rollback strategy
3. Validation strategy split by:
   - local build checks
   - extension install/signing checks
   - app-level runtime checks

## Guardrails

- Keep IPC and media format contracts explicit and versioned.
- Avoid introducing avoidable frame copies.
- Treat signing limitations as engineering constraints, not optional tasks.
