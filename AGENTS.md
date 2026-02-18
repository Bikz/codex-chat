# CodexChat Repository Instructions

## Product Direction
- Build CodexChat as a macOS-native, two-pane chat product.
- Keep the conversation canvas primary and avoid a persistent third pane in release one.
- Prioritize legibility, safety, and user-controlled local context.

## Source Of Truth
1. `AGENTS.md`
2. `README.md`
3. `docs-public/` (tracked public documentation)
4. Private `docs/` (local planning memory, ignored by git)
5. Code reality

## Delivery Rules
- Work one epic at a time.
- Use small, atomic commits.
- Keep builds/tests green.
- Ship empty/loading/error states for user-facing surfaces.
- Accessibility basics are required, not optional.

## Dev Loop

- Fast checks: `make quick`
- Full checks: `pnpm -s run check`

## Repo Conventions

- Keep the repo steerable: when a Swift file grows beyond ~500 LOC, split it into focused types or `TypeName+Feature.swift` extensions.
- Do not add a persistent third pane in the initial releases. Use sheets/cards/drawers for auxiliary UI.
- `docs/` is private/untracked by design. Do not add tracked files under `docs/`; use `docs-public/` instead.
- Never log secrets (API keys, auth tokens). Avoid printing credentials in tests and diagnostics exports.
