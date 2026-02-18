# Contributing

## Core Guardrails

- Preserve two-pane IA (sidebar + conversation canvas).
- Do not add a persistent third pane.
- Ship empty/loading/error states for user-facing surfaces.
- Keep keyboard navigation, focus visibility, and contrast accessible.
- Never log secrets.

## Module Boundaries

- `apps/CodexChatHost`: canonical GUI host (`@main`, bundle identity, assets, release surface).
- `apps/CodexChatApp`: `CodexChatShared` (shared behavior) + `CodexChatCLI` (headless contributor tooling).
- `packages/*`: reusable packages.

Do not duplicate app/runtime logic in host or CLI shells.

## Local Workflow

```sh
corepack enable
pnpm install
make quick
pnpm -s run check
```

## Preferred Run Paths

- GUI QA and feature verification: `CodexChatHost` scheme in Xcode.
- Deterministic diagnostics/repro: `swift run CodexChatCLI ...`.

## Code Quality Expectations

- Keep changes focused and atomic.
- Add regression tests for bug fixes when feasible.
- Keep files steerable (split very large files).
- Prefer token-driven UI surfaces over one-off styling.
