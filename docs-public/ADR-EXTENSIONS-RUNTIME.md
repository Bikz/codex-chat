# ADR: Extension Runtime v1 (Hooks + Automations + Optional Mods bar)

## Status

Accepted (experimental API).

## Context

CodexChat needed a first-class extension model beyond theme overrides so third-party developers can build:

- turn/thread lifecycle hooks
- scheduled automations
- contextual modsBar output without changing default two-pane IA

## Decision

- Use `ui.mod.json` `schemaVersion: 1` as the clean-slate runtime contract for theme + extension sections (`hooks`, `automations`, `uiSlots`).
- Keep theme parsing in `CodexMods`.
- Add extension runtime primitives in `packages/CodexExtensions`.
- Execute extension handlers as isolated subprocesses over stdio JSONL.
- Keep two-pane default IA; expose only an optional, collapsed-by-default right modsBar slot.
- Gate privileged extension behavior with per-mod permission prompts.
- Require one-time global consent for background automations when app is closed.

## Consequences

Positive:

- Local-first extension ecosystem without embedding third-party code in-process.
- Predictable event contract for summaries, note syncing, and automation workflows.
- Explicit permission model and constrained artifact writes.

Tradeoffs:

- API is marked experimental and may require migration in future versions.
- Background execution depends on launchd registration and user consent.
- Hook/automation handlers must conform to strict JSONL protocol and timeout bounds.
