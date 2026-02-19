# Extensions Quickstart (vNext)

This guide shows the fastest path to build and install a CodexChat extension package.

## 1) Generate a starter package

In CodexChat:

1. Open `Skills & Mods` -> `Mods`.
2. Click `Create Sample` in Global or Project scope.
3. Open the generated folder.

The sample now includes:

- `codex.mod.json` (package manifest)
- `ui.mod.json` (runtime config)
- `scripts/hook.sh`
- `scripts/automation.sh`

## 2) Implement a thread summary extension

Edit `scripts/hook.sh` to emit modsBar markdown.

Input: one JSON line from CodexChat.
Output: one JSON line, for example:

```json
{"ok":true,"modsBar":{"title":"Thread Summary","markdown":"- Turn completed"}}
```

Then keep `ui.mod.json` hook bound to `turn.completed` and `uiSlots.modsBar`.

Keep `ui.mod.json` on `schemaVersion: 1` and do not use legacy `uiSlots.rightInspector`.

## 3) Validate your package metadata

In `codex.mod.json`:

- keep `id/name/version` aligned with `ui.mod.json.manifest`
- ensure `permissions` includes all permissions used by hooks/automations
- set `entrypoints.uiMod` to `ui.mod.json` (or another safe relative path)
- optionally set `integrity.uiModSha256`
- `codex.mod.json` is required for install (no legacy fallback)

## 4) Install from local path or GitHub URL

In CodexChat:

1. `Skills & Mods` -> `Mods` -> `Install Mod`
2. Enter either:
   - local folder path
   - GitHub URL (for example `https://github.com/org/mod-repo.git`)
   - GitHub tree subdirectory URL (for example `https://github.com/org/repo/tree/main/mods/first-party/thread-summary`)
3. Choose scope: Project or Global.
4. Click `Review Package`, confirm metadata + permissions, then install.

The mod is auto-enabled after install.

## 5) Permission prompts

If your extension requests privileged permissions (`projectWrite`, `network`, `runtimeControl`, `runWhenAppClosed`), CodexChat prompts on first use.

## 6) Share with others

1. Commit your extension folder to git.
2. Share repo URL.
3. Others install via `Install Mod`.

## Patterns For Common Extensions

1. Personal Notes (per chat):
- use `turn.completed` hook + modsBar markdown + optional `artifacts` writes under project root.

2. Thread Summary:
- emit one-line bullet updates in modsBar markdown after each turn.

3. Prompt Book (cross-chat launcher):
- use `modsBar.scope: global` + `modsBar.actions` with `composer.insertAndSend`.
- use `modsBar.action` hooks for add/edit/delete prompt management.
