# Prompt Book Mod

Global reusable prompts in the CodexChat Mods bar.

## Behavior

- Stores a global prompt list (shared across chats/projects).
- One-click `Send` actions use `composer.insertAndSend`.
- Supports add/edit/delete management actions.

## Prompt Input Format

- `Title :: Prompt body`
- Or just `Prompt body` (title auto-derived)

## Install

- Local path: this folder
- GitHub URL: repository URL (optionally with `/tree/<branch>/mods/first-party/prompt-book`)
- GitHub `blob` URLs are unsupported. Use a repository root URL or `tree` URL.

## Runtime

- Uses default macOS tooling only: `sh`, `plutil`, `osascript`.
