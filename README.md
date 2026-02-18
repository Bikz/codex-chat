# CodexChat

CodexChat is a macOS 26-native SwiftUI app focused on safe, local-first agentic chat workflows.

## Prompt 1 Baseline Goals
- Two-pane shell: sidebar for projects/threads + conversation canvas.
- Modular architecture across Swift packages.
- Local metadata persistence for projects, threads, and last-opened context.
- Design tokens with injectable theming for future mods.
- Hidden diagnostics surface with runtime placeholder and logs.

## Repository Layout
- `apps/CodexChatApp`: macOS app entrypoint.
- `packages/*`: modular Swift packages (`UI`, `Core`, `Infra`, `CodexKit`, `Skills`, `Memory`, `Mods`).
- `.github/workflows`: CI workflows.
- `docs/`: local private planning memory (ignored by git by design).

## Local Setup
1. Install Xcode 26+.
2. Ensure Swift 6.2+ is available.
3. Use `pnpm` for non-Swift tooling scaffolding.
4. Build and test from package directories:
   - `cd apps/CodexChatApp && swift build && swift test`
   - `cd packages/CodexChatInfra && swift test`

## Notes
- `docs/` intentionally remains private and untracked.
- Prompt 1 uses runtime placeholders only (no live Codex app-server event integration yet).
