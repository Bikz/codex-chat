# Contributing

## First Hour Setup

```sh
bash scripts/bootstrap.sh
make oss-smoke
```

This gives you a validated local toolchain, fast checks, CLI health checks, and an unsigned host app build.

## Core Guardrails

- Preserve two-pane IA (sidebar + conversation canvas).
- Do not add a persistent third pane.
- Ship empty/loading/error states for user-facing surfaces.
- Keep keyboard navigation, focus visibility, and contrast accessible.
- Never log secrets or auth material.

## Module Boundaries

- `apps/CodexChatHost`: canonical GUI host (`@main`, bundle identity, assets, signing/release surface).
- `apps/CodexChatApp`: `CodexChatShared` (shared behavior) + `CodexChatCLI` (headless contributor tooling).
- `packages/*`: reusable libraries.

Do not duplicate app/runtime logic in host or CLI shells.

## Preferred Run Paths

- GUI QA and user behavior checks: open `apps/CodexChatHost/CodexChatHost.xcodeproj` and run `CodexChatHost`.
- Deterministic diagnostics and repro: run from `apps/CodexChatApp` with `swift run CodexChatCLI doctor|smoke|repro`.
- Runtime protocol mismatches (`unknown variant`, `missing field`, `invalid request`) usually indicate an outdated Codex CLI; update `codex` and retry before filing runtime bugs.

## Local Validation Before PR

```sh
make quick
make oss-smoke
pnpm -s run check
```

## Issue Filing Requirements

Use the bug template and include:

- `swift run CodexChatCLI doctor` output (from `apps/CodexChatApp`)
- `swift run CodexChatCLI smoke` output (from `apps/CodexChatApp`)
- deterministic repro fixture (`repro --fixture <name>`) or minimal step list
- whether the issue reproduces in `CodexChatHost`

Issues that lack deterministic repro details may be labeled `needs-repro`.

## Label Semantics

- `bug`: confirmed incorrect behavior
- `enhancement`: product/UX improvement request
- `needs-repro`: missing deterministic reproduction data

## Maintainer Triage Targets

- New issues: first triage pass within 3 business days.
- New PRs: first review pass within 3 business days when CI is green.
- `needs-repro` issues without follow-up details may be closed after 14 days.

## PR Expectations

- Keep scope atomic and focused.
- Add regression tests for bug fixes when feasible.
- Update docs when run path, architecture, or release behavior changes.
- Keep host/CLI/shared boundaries consistent with `docs-public/ARCHITECTURE_CONTRACT.md`.
