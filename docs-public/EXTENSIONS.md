# Extensions API (Experimental)

CodexChat exposes an experimental extension runtime on top of `ui.mod.json` (`schemaVersion: 2`).

## Supported Extension Surfaces

- `hooks`: run handlers on runtime/thread/turn lifecycle events
- `automations`: run scheduled handlers using cron expressions
- `uiSlots.rightInspector`: optional right inspector pane (collapsed by default)

## Hook Events (v1)

- `thread.started`
- `turn.started`
- `assistant.delta`
- `action.card`
- `approval.requested`
- `turn.completed`
- `turn.failed`
- `transcript.persisted`

## Worker Protocol (stdio JSONL)

Input line shape:

```json
{"protocol":"codexchat.extension.v1","event":"turn.completed","timestamp":"...","project":{"id":"...","path":"..."},"thread":{"id":"..."},"turn":{"id":"...","status":"completed"},"payload":{}}
```

Output line shape:

```json
{"ok":true,"inspector":{"title":"Current turn","markdown":"One-line summary..."},"artifacts":[{"path":"notes/summary.md","op":"upsert","content":"..."}],"log":"..."}
```

Rules:

- one request event per process invocation
- non-zero exit or malformed JSON marks execution as failed
- unknown output fields are ignored

## Permissions

Per-hook/per-automation permission keys:

- `projectRead`
- `projectWrite`
- `network`
- `runtimeControl`
- `runWhenAppClosed`

Auto-enable on install does not bypass permission prompts.

## Scheduling

- App-open execution uses in-app scheduler.
- App-closed execution uses launchd only when:
  - extension requests `runWhenAppClosed`
  - global background permission is granted
  - per-mod permission is granted

## Catalog

Mods UI can consume an optional remote catalog index provider. Supported listing fields include:

- `id`, `name`, `version`, `summary`
- `repositoryURL`, `downloadURL`, `checksum`
- `rankingScore`, `trustMetadata`

## Inspector Slot Contract

`uiSlots.rightInspector` is optional and non-persistent by default:

- toolbar toggle: `Inspector`
- collapsed on launch
- rendered only when active mod enables it

## Stability

This API is experimental and may change across minor versions.
