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
- `Mods bar` can be shown in docked modes that push conversation content inward; it must never overlay transcript content by default.

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
- `manifest`: `id`, `name`, `version` (+ optional metadata, including `iconSymbol`)
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
- users can toggle `Mods bar` even before the first message in a new chat (project selected, draft thread)
- content is sourced from extension worker output
- visibility and presentation mode are persisted globally across chats/new threads (`hidden`/`rail`/`peek`/`expanded`)
- reopening from `hidden` restores the last open non-rail mode (`peek` or `expanded`)
- `rail` mode is an icon launcher strip intended for quick extension switching
- duplicate entries are deduplicated in `rail` when the same mod id is installed in both project/global roots
- output may be `thread`, `project`, or `global` scope
- output may include typed action buttons (`emitEvent`, `promptThenEmitEvent`, `composer.insert`, `composer.insertAndSend`, `native.action`)

`uiSlots.modsBar` fields:

- `enabled` (required): whether the mod exposes a mods bar surface
- `title` (optional): display title
- `requiresThread` (optional, default `true`): if `false`, the mod can run in draft mode without a selected thread
- `source` (optional): handler output binding

In `Skills & Mods -> Mods`, runtime enablement is now separate from active selection:

- `Runtime On/Off` controls whether hooks/automations/modsBar surfaces participate
- `Set Active` chooses which scoped mod is currently focused in the panel

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

## Native Action Bridge

Mods bar actions can dispatch native computer actions through:

- `kind: "native.action"`
- `nativeActionID` (or `payload.actionID`) to select the native action
- optional metadata (`safetyLevel`, `requiresConfirmation`, `externallyVisible`) for install/review surfaces

Current first-party native actions:

- `desktop.cleanup`
- `calendar.today`
- `calendar.create`
- `calendar.update`
- `calendar.delete`
- `reminders.today`
- `messages.send`
- `files.read`
- `files.move`
- `apple.script.run`

Native actions still execute through CodexChat safety rules (preview + confirmation for sensitive actions).

For explicit Codex-led workflows (instead of direct native action dispatch), first-party `personal-actions-playbook` provides `composer.insert` playbooks that keep clarify/preview/confirm steps visible in chat.

## Advanced Executable Mods Unlock

Executable mod behavior (hooks/automations) for non-vetted mods is gated by an advanced unlock in Settings.

- Existing users retain legacy behavior.
- New users default to locked advanced executable mods.
- Vetted first-party packs are exempt from this lock.
