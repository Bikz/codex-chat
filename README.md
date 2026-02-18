# CodexChat

CodexChat is a local-first macOS SwiftUI chat app that integrates the local Codex runtime (app-server) so everyday users can safely benefit from agentic capabilities (files, commands, skills, artifacts).

## Product Rules

- Default UI is **two-pane**: sidebar (Projects + Threads) + conversation canvas.
- A persistent third pane is future scope (the architecture is designed to support it later).

## Key Features

- Projects as real folders (trusted/untrusted) with per-project safety settings.
- Streaming assistant responses in the transcript.
- Inline, reviewable Action Cards (tool runs, file changes, approvals).
- Local chat archives written as Markdown in the project for grep/search.
- Per-thread persistent follow-up queue: Enter sends when idle, auto-queues when busy, with edit/delete/re-prioritize and Auto FIFO drain.
- In-flight `Steer` dispatch for capable runtimes, with deterministic fallback to "queue next" on legacy runtimes.
- Skills discovery + install + per-project enablement (progressive disclosure).
- Memory system stored as editable project files, with optional advanced retrieval.
- System light/dark defaults with UI Mods overrides (including optional dark-specific overrides) and precedence `defaults < global < project`, hot reload, and **mandatory review** for agent-proposed mod edits.
- Tokenized card/panel surfaces across sidebar lists and major sheets/canvases so Mods material overrides apply consistently.
- Composer input uses tokenized body typography and supports `Cmd+Return` to send.
- First-class Shell Workspace drawer with per-project multi-session shell panes, recursive splits, and close/restart controls.
- Diagnostics surface for runtime status + logs.

## Repo Layout

- `apps/CodexChatApp`: macOS app.
- `packages/*`: modular Swift packages (`Core`, `Infra`, `UI`, `CodexKit`, `Skills`, `Memory`, `Mods`).
- `.github/workflows`: CI.
- `docs/`: private planning memory (ignored by git by design).
- `docs-public/`: public documentation (tracked).

## Build + Test

### Requirements

- macOS 13+
- Xcode 16+ (Swift tools version `6.0`)
- Homebrew
- Node 22+ (for `corepack` / `pnpm` and git hooks)
- **gitleaks** (for secret scanning): `brew install gitleaks`
- **SwiftLint** (for linting): `brew install swiftlint`
- **SwiftFormat** (for formatting): `brew install swiftformat`

### Setup

From the repo root:

```sh
corepack enable
pnpm install

brew install swiftformat swiftlint gitleaks
```

### Full Checks

From the repo root:

```sh
pnpm -s run check
```

### Fast Checks

```sh
make quick
```

## Docs

- `docs-public/INSTALL.md`
- `docs-public/SECURITY_MODEL.md`
- `docs-public/MODS.md`
- `docs-public/CONTRIBUTING.md`

## License

MIT License. See `LICENSE`.
