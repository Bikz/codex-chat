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

CLI alternative:

```bash
CodexChatCLI mod init --name "Thread Summary" --output /path/to/mods
```

## 2) Implement a thread summary extension

Edit `scripts/hook.sh` to emit modsBar markdown.

Input: one JSON line from CodexChat.
Output: one JSON line, for example:

```json
{"ok":true,"modsBar":{"title":"Thread Summary","markdown":"- Turn completed"}}
```

Then keep `ui.mod.json` hook bound to `turn.completed` and `uiSlots.modsBar`.

Keep `ui.mod.json` on `schemaVersion: 1` and do not use legacy `uiSlots.rightInspector`.
Use `modsBar.scope` as needed: `thread`, `project`, or `global`.

### Runtime baseline for no-dependency mods

For widest user compatibility on macOS, prefer built-in tools:

- `sh`
- `plutil`
- `osascript` (only when you need robust JSON escaping/serialization)

## 3) Validate your package metadata

In `codex.mod.json`:

- keep `id/name/version` aligned with `ui.mod.json.manifest`
- ensure `permissions` includes all permissions used by hooks/automations
- set `entrypoints.uiMod` to `ui.mod.json` (or another safe relative path)
- optionally set `integrity.uiModSha256` (samples do not scaffold integrity by default)
- `codex.mod.json` is required for install (no legacy fallback)

Validate from CLI (local path or GitHub URL):

```bash
CodexChatCLI mod validate --source /path/to/mods/thread-summary
CodexChatCLI mod inspect-source --source https://github.com/org/repo/tree/main/mods/thread-summary
```

## 4) Install from local path or GitHub URL

In CodexChat:

1. `Skills & Mods` -> `Mods` -> `Install Mod`
2. Enter either:
   - local folder path
   - GitHub URL (for example `https://github.com/org/mod-repo.git`)
   - GitHub tree subdirectory URL (for example `https://github.com/org/repo/tree/main/mods/first-party/thread-summary`)
   - note: GitHub `blob` URLs are rejected. Convert them to `tree` URLs.
3. Choose scope: Project or Global.
4. Click `Review Package`, confirm metadata + permissions, then install.

Enablement after install:
- Most mods are enabled immediately after install.
- If the mod contains executable hooks/automations and is not vetted first-party, it can install as disabled when advanced executable mods are locked in Settings.
- In that case, unlock advanced executable mods (Settings -> Experimental) before enabling.

## 5) Permission prompts

If your extension requests privileged permissions (`projectWrite`, `network`, `runtimeControl`, `runWhenAppClosed`), CodexChat prompts on first use.

## 6) Share with others

1. Commit your extension folder to git.
2. Share repo URL.
3. Others install via `Install Mod`.

## Mods Bar UX Behavior (Current)

- Mods bar is collapsed by default, then persisted globally once user toggles it.
- Visibility/presentation carries across existing chats and brand-new drafts in the selected project.
- Modes:
  - `rail`: compact launcher strip with extension quick-switch icons
  - `peek`: standard docked panel
  - `expanded`: wider docked panel for dense extension UIs
- Closing from `rail` hides the panel fully; reopening restores the last open non-rail mode.
- When the same mod id exists in both project and global scope, rail quick-switch deduplicates to one entry.
- Add `uiSlots.modsBar.requiresThread: false` for mods that should work in draft mode without a selected thread.
- Optionally set `manifest.iconSymbol` to control the Mods bar rail icon.

## Patterns For Common Extensions

1. Personal Notes (per chat):
- use `turn.completed` hook + modsBar markdown + optional `artifacts` writes under project root.

2. Thread Summary:
- emit one-line bullet updates in modsBar markdown after each turn.

3. Prompt Book (cross-chat launcher):
- use `modsBar.scope: global` + `modsBar.actions` with `composer.insertAndSend`.
- use `modsBar.action` hooks for add/edit/delete prompt management.
- Prompt Book works best with global mods-bar persistence because the panel state is shared across chats/new drafts.
