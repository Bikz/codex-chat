# Create And Share Skills + Mods

CodexChat supports both Skills and UI Mods. This page is the canonical builder guide for mod authoring, including extension surfaces (`schemaVersion: 2`).

## Skills Quickstart

1. Create a folder with `SKILL.md`.
2. Add any helper scripts under `scripts/` if needed.
3. Push to git and share the repo URL.
4. In CodexChat, open `Skills`, install, and enable per project.

## Mod Quickstart

1. Open `Skills & Mods` -> `Mods`.
2. Click `Create Sample` in Global Mod or Project Mod.
3. Edit the generated `ui.mod.json`.
4. Select the mod in the Mods picker.

Mod roots:

- Global: `~/CodexChat/global/mods`
- Project: `<project>/mods`

Precedence:

- `defaults < global mod < project mod`

## What You Can Build

1. Theme Packs (`schemaVersion: 1/2`): visual token overrides.
2. Turn/Thread Hooks: event-driven summaries or side effects.
3. Scheduled Automations: cron-driven jobs (notes sync, logging, exports).
4. Right Inspector Panels: optional toolbar-toggled inspector content.

Extension APIs are experimental and may change in minor releases.

## `ui.mod.json` Schema

### v1 (theme-only)

```json
{
  "schemaVersion": 1,
  "manifest": {
    "id": "acme.theme.solarized",
    "name": "Solarized Theme",
    "version": "1.0.0"
  },
  "theme": {
    "palette": {
      "accentHex": "#268BD2",
      "backgroundHex": "#FDF6E3",
      "panelHex": "#EEE8D5"
    }
  }
}
```

### v2 (theme + extensions)

```json
{
  "schemaVersion": 2,
  "manifest": {
    "id": "acme.extension.summary",
    "name": "Summary Sidebar",
    "version": "1.0.0"
  },
  "theme": {},
  "hooks": [
    {
      "id": "turn-summary",
      "event": "turn.completed",
      "handler": {
        "command": ["node", "scripts/hook.js"],
        "cwd": "."
      },
      "permissions": {
        "projectRead": true,
        "projectWrite": false,
        "network": false,
        "runtimeControl": false
      },
      "timeoutMs": 8000,
      "debounceMs": 0
    }
  ],
  "automations": [
    {
      "id": "daily-notes",
      "schedule": "0 9 * * *",
      "handler": {
        "command": ["python3", "scripts/automation.py"],
        "cwd": "."
      },
      "permissions": {
        "projectRead": true,
        "projectWrite": true,
        "network": false,
        "runWhenAppClosed": true
      },
      "timeoutMs": 60000
    }
  ],
  "uiSlots": {
    "rightInspector": {
      "enabled": true,
      "title": "Summary",
      "source": {
        "type": "handlerOutput",
        "hookId": "turn-summary"
      }
    }
  }
}
```

Top-level fields:

- `schemaVersion`: `1` or `2`
- `manifest`: `id`, `name`, `version`, optional metadata
- `theme`, optional `darkTheme`: theme token overrides
- `hooks` (v2 optional): event handlers
- `automations` (v2 optional): scheduled handlers
- `uiSlots` (v2 optional): optional inspector slot

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

Input line:

```json
{"protocol":"codexchat.extension.v1","event":"turn.completed","timestamp":"...","project":{"id":"...","path":"..."},"thread":{"id":"..."},"turn":{"id":"...","status":"completed"},"payload":{}}
```

Output line:

```json
{"ok":true,"inspector":{"title":"Current turn","markdown":"One-line summary..."},"artifacts":[{"path":"notes/summary.md","op":"upsert","content":"..."}],"log":"..."}
```

Rules:

- One request event per process invocation.
- Non-zero exit or malformed JSON marks execution as failed.
- Unknown response fields are ignored.

## Permissions And Safety

Permission keys:

- `projectRead`
- `projectWrite`
- `network`
- `runtimeControl`
- `runWhenAppClosed`

Behavior:

- Install auto-enables a mod.
- Auto-enable does not bypass permission prompts.
- Privileged actions prompt on first use.
- Worker execution is bounded by timeout and output caps.

## Automations And Background Execution

- When app is open, automations run in-app.
- App-closed runs use launchd only when:
  - automation requests `runWhenAppClosed: true`
  - global background permission is granted
  - per-mod permissions are granted
- Background permission is prompted once globally, then enforced per automation.

## Inspector Slot Contract

`uiSlots.rightInspector` is optional.

- Two-pane default remains unchanged.
- Inspector is collapsed by default.
- Users reveal it via toolbar `Inspector` toggle.
- Content comes from the active mod.
- The inspector surface is non-persistent by default behavior.

## Packaging, Sharing, And Install

1. Keep each mod in its own folder containing `ui.mod.json`.
2. Commit the folder/repo to git.
3. Share the repo URL.
4. In CodexChat, use `Install Mod` (global or project scope).
5. Mod installs auto-enable immediately.
6. First privileged hook/automation run prompts for permissions.

## Compatibility

- `schemaVersion: 1` mods continue to work unchanged.
- `schemaVersion: 2` enables hooks/automations/inspector surfaces.
- If v2 sections are invalid, theme behavior remains available and extension surfaces are disabled.

## Related Docs

- `MODS.md` (theme format and precedence reference)
- `EXTENSIONS.md` (compatibility landing page)
- `ADR-EXTENSIONS-RUNTIME.md` (runtime architecture)
