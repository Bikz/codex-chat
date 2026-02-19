# Developer Agent Workflows

CodexChat includes developer-focused upgrades for multi-agent reliability and transparency while keeping the same conversation-first UX.

## Worker Transparency

Runtime action payloads can now include worker/subagent trace metadata.

- Trace metadata is decoded and preserved with action cards.
- UI can surface worker details from turn summaries.
- When runtime omits trace payloads, CodexChat displays `trace unavailable from runtime`.

## Role/Profile Builder

Settings -> Codex Config now supports guided authoring for:

- `profiles.<name>` model presets
- `agents.<role>.description`
- `agents.<role>.config_file`
- role config template files under `.codex/agents/*.toml`

The builder updates config draft state, keeps raw TOML editing available, and supports writing role templates to disk.

## Dependency-Aware Plan Runner Primitives

Plan runner core logic includes:

- Markdown plan parsing into structured tasks and dependencies
- unknown dependency detection
- cycle detection in dependency graphs
- unblocked batch scheduling from completed task sets
- sequential fallback when multi-agent execution is disabled

These primitives are implemented as app-layer types (`PlanParser`, `PlanScheduler`) for future execution surfaces.

## Mods + Native Actions (Hybrid Policy)

Developer mods can dispatch native actions via `kind: "native.action"` while preserving safety controls.

- Native action metadata (`nativeActionID`, `safetyLevel`, etc.) is supported in extension action payloads.
- Non-vetted executable mods are guarded by the advanced unlock setting.
- Vetted first-party packs remain available by default.

## Operational Notes

- Existing users preserve prior defaults after migration.
- New installs default to stricter executable-mod gating.
- All changes preserve the two-pane IA contract.
