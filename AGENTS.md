# resolvekit-ios-sdk

This file is the **table of contents** for coding agents. Keep it short, stable, and current.

## Working Contract

- Humans define intent and quality bars.
- Agents implement code, tests, docs, and CI changes.
- Repository markdown is the source of truth for architecture and process.
- Behavior changes must include docs updates in the same PR.

## First Read

1. `README.md` for package integration and runtime model.
2. `docs/INDEX.md` for repository knowledge map.
3. `docs/agent-first/README.md` for harness principles.

## Commands

```bash
swift build
swift test
```

## Source of Truth Layout

- `Sources/` SDK runtime, UI, and authoring layers.
- `Tests/` contract and integration tests.
- `docs/INDEX.md` documentation entry point.
- `docs/exec-plans/` plan history and technical debt tracking.

## Guardrails

- No secrets or private credentials in repo.
- Preserve public API compatibility unless explicitly planned.
- Keep defaults self-host-friendly and documented.
- Run `bash scripts/check_agent_docs.sh` when changing docs structure.
