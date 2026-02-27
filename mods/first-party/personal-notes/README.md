# Personal Notes Mod

Project-scoped notes inside the CodexChat Mods bar.

## Behavior

- Shows project notes in the Mods bar across all threads and draft/new chats.
- In current CodexChat builds, notes are editable inline and autosave per project.
- `Add / Edit Note` remains available for compatibility with older app builds.
- `Clear Note` clears the current project note.

## Authoring Note

- This mod intentionally sets `uiSlots.modsBar.requiresThread: false` so it works without a selected thread.

## Install

- Local path: this folder
- GitHub URL: repository URL (optionally with `/tree/<branch>/mods/first-party/personal-notes`)
- GitHub `blob` URLs are unsupported. Use a repository root URL or `tree` URL.

## Runtime

- Uses default macOS tooling only: `sh`, `plutil`, `osascript`.
