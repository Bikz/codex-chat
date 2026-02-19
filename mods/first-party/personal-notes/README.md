# Personal Notes Mod

Per-thread notes inside the CodexChat Mods bar.

## Behavior

- Shows thread-specific notes in the Mods bar.
- `Add / Edit Note` prompts for text and persists it to thread state.
- `Clear Note` clears the current thread note.

## Install

- Local path: this folder
- GitHub URL: repository URL (optionally with `/tree/<branch>/mods/first-party/personal-notes`)
- GitHub `blob` URLs are unsupported. Use a repository root URL or `tree` URL.

## Runtime

- Uses default macOS tooling only: `sh`, `plutil`, `osascript`.
