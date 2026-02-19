# ADR: Mods Runtime Schema Reset To v1

## Status

Accepted.

## Context

The prior extension rollout mixed:

- `ui.mod.json` schema evolution (`1` for theme, `2` for hooks/automations/ui slots)
- legacy naming (`rightInspector`)
- inconsistent docs and user-facing copy

This created builder confusion and hidden compatibility behavior that conflicted with reliability-first product constraints.

## Decision

1. Reset `ui.mod.json` runtime contract to a single clean-slate `schemaVersion: 1`.
2. Reject legacy runtime contracts at load/install time:
   - `schemaVersion: 2`
   - `uiSlots.rightInspector`
3. Standardize naming to `Mods bar` user-facing and `modsBar` in manifests/runtime payloads.
4. Keep `codex.mod.json` package schema at `schemaVersion: 1` and enforce compatibility/integrity validation.
5. Require `codex.mod.json` for install (no legacy `ui.mod.json`-only fallback path).
6. Publish explicit migration errors guiding developers to:
   - set `schemaVersion: 1`
   - rename `uiSlots.rightInspector` to `uiSlots.modsBar`
   - add `codex.mod.json` with `schemaVersion: 1` and matching `id/name/version`

## Consequences

Positive:

- One canonical runtime schema for third-party builders.
- Clear install/load failures for unsupported legacy mods.
- Lower maintenance burden and fewer hidden branches.

Tradeoffs:

- Breaking change for older third-party mods.
- Existing mod authors must migrate manifests before install.

## Follow-up

1. Add migration examples for common mod patterns (Notes, Thread Summary, Prompt Book).
2. Add release notes calling out the breaking change.
3. Keep GitHub install as primary channel while catalog hardens.
