# Thread Summary Mod

One-line timeline updates in the CodexChat Mods bar after each turn.

## Behavior

- Appends one summary line for each completed/failed turn.
- Persists timeline per thread.
- Keeps only the latest 40 lines.
- `Clear Timeline` resets the current thread summary.

## Install

- Local path: this folder
- GitHub URL: repository URL (optionally with `/tree/<branch>/mods/first-party/thread-summary`)
- GitHub `blob` URLs are unsupported. Use a repository root URL or `tree` URL.

## Runtime

- Uses default macOS tooling only: `sh`, `plutil`, `osascript`.
