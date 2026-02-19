# Create And Share Skills + Mods

Canonical builder guide for CodexChat mods.

## Skills Quickstart

1. Create a folder with `SKILL.md`.
2. Add helper scripts under `scripts/` if needed.
3. Push to GitHub and share the repo URL.
4. In CodexChat, open `Skills`, install, and enable.

## Mods Quickstart

1. Open `Skills & Mods` -> `Mods`.
2. Click `Create Sample` in Global Mod or Project Mod.
3. Edit `ui.mod.json` and `codex.mod.json`.
4. Review + install from local path or GitHub URL.

Mod roots:

- Global: `~/CodexChat/global/mods`
- Project: `<project>/mods`

Precedence:

- `defaults < global mod < project mod`

## What You Can Build

1. Theme packs.
2. Slash command and workflow helper mods.
3. Turn/thread summary and automation mods.
4. `Mods bar` UI experiences (`uiSlots.modsBar`).

## Package Layout

```text
<mod-root>/
  codex.mod.json
  ui.mod.json
  scripts/
  README.md
```

## `ui.mod.json` Schema

`schemaVersion` must be `1`.

```json
{
  "schemaVersion": 1,
  "manifest": {
    "id": "acme.thread-summary",
    "name": "Thread Summary",
    "version": "1.0.0"
  },
  "theme": {},
  "hooks": [
    {
      "id": "turn-summary",
      "event": "turn.completed",
      "handler": { "command": ["sh", "scripts/hook.sh"], "cwd": "." },
      "permissions": { "projectRead": true },
      "timeoutMs": 8000
    }
  ],
  "uiSlots": {
    "modsBar": {
      "enabled": true,
      "title": "Thread Summary",
      "source": { "type": "handlerOutput", "hookId": "turn-summary" }
    }
  }
}
```

Unsupported legacy inputs:

- `schemaVersion: 2`
- `uiSlots.rightInspector`

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

## Worker Protocol

Input (one JSON line):

```json
{"protocol":"codexchat.extension.v1","event":"turn.completed","timestamp":"...","project":{"id":"...","path":"..."},"thread":{"id":"..."},"payload":{}}
```

Output:

```json
{"ok":true,"modsBar":{"title":"Thread Summary","scope":"thread","markdown":"- Turn completed","actions":[{"id":"clear","label":"Clear","kind":"emitEvent","payload":{"operation":"clear","targetHookID":"summary-action"}}]},"artifacts":[{"path":"notes/summary.md","op":"upsert","content":"..."}]}
```

## Permissions And Safety

Permission keys:

- `projectRead`
- `projectWrite`
- `network`
- `runtimeControl`
- `runWhenAppClosed`

Rules:

- install does not auto-grant privileged permissions
- privileged behavior is prompted on first use
- automations are timeout-bounded

## `Mods bar` Contract

- Two-pane layout remains unchanged.
- `Mods bar` is user-toggled and collapsed by default.
- Content comes from `uiSlots.modsBar` + worker output.

## Install And Sharing

1. Commit your mod package to GitHub.
2. In CodexChat, open `Install Mod`.
3. Review package metadata + permissions.
4. Install to global or project scope.

Repository policy for this cycle:

- first-party exemplar mods live under `mods/first-party` in the CodexChat repo
- third-party mods should stay in external GitHub repositories (or local folders)
- no hosted catalog onboarding in this cycle

## Related Docs

- `MODS.md`
- `EXTENSIONS.md`
- `EXTENSIONS_SPEC_VNEXT.md`
