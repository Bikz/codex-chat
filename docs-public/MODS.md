# UI Mods

CodexChat mods can:

- override theme tokens
- run turn/thread hook handlers
- run scheduled automation handlers
- render optional `Mods bar` content through `uiSlots.modsBar`

## Product Constraints

- Two-pane IA is non-negotiable.
- `Mods bar` is optional and collapsed by default.
- No persistent third pane.

## Mod Roots

- Global: `~/CodexChat/global/mods`
- Project: `<project>/mods`

## Precedence

`defaults < global mod < project mod`

## Required Files

Each mod package should contain:

```text
<mod-root>/
  ui.mod.json
  codex.mod.json
```

`ui.mod.json` is the runtime contract.
`codex.mod.json` is the install/distribution contract.

## `ui.mod.json` Contract

Top-level fields:

- `schemaVersion`: must be `1`
- `manifest`: `id`, `name`, `version` (+ optional metadata)
- `theme` and optional `darkTheme`
- `hooks` (optional array)
- `automations` (optional array)
- `uiSlots` (optional object, supports `modsBar`)
- `future` (optional, reserved)

Legacy keys are rejected:

- `uiSlots.rightInspector` is unsupported
- `schemaVersion: 2` is unsupported

## `uiSlots.modsBar`

`uiSlots.modsBar` is optional. When enabled:

- users can toggle `Mods bar` from the toolbar
- content is sourced from extension worker output
- the surface stays non-persistent by default
- output may be `thread` or `global` scope
- output may include typed action buttons (`emitEvent`, `promptThenEmitEvent`, `composer.insert`, `composer.insertAndSend`)

## Hook Events

- `thread.started`
- `turn.started`
- `assistant.delta`
- `action.card`
- `approval.requested`
- `modsBar.action`
- `turn.completed`
- `turn.failed`
- `transcript.persisted`

## Permissions

Permission keys:

- `projectRead`
- `projectWrite`
- `network`
- `runtimeControl`
- `runWhenAppClosed`

Permission prompts are runtime-gated on first privileged use.
