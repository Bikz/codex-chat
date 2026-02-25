# Contributing

CodexChat is a local-first, macOS-native SwiftUI app. Contributions should keep behavior reliable, legible, and safe for agent-driven workflows.

## First Hour Setup

```sh
bash scripts/bootstrap.sh
make oss-smoke
```

This validates local tooling, runs fast checks, and verifies contributor smoke flows.

## Core Guardrails

- Keep the conversation-first app model and existing information architecture.
- Ship empty/loading/error states for user-facing surfaces.
- Keep keyboard navigation, focus visibility, and contrast accessible.
- Never log secrets or auth material.
- Do not introduce hidden behavior for dangerous actions; keep approvals explicit.

## Module Boundaries

- `apps/CodexChatHost`: canonical GUI host (`@main`, bundle identity, assets, signing/release surface).
- `apps/CodexChatApp`: `CodexChatShared` behavior and `CodexChatCLI` headless contributor tooling.
- `packages/*`: reusable libraries (`Core`, `Infra`, `UI`, `CodexKit`, `Skills`, `Memory`, `Mods`, `Extensions`).

Do not duplicate core app/runtime behavior in host or CLI shells.

## Preferred Run Paths

- GUI QA and user behavior checks:

```sh
open apps/CodexChatHost/CodexChatHost.xcodeproj
```

Run scheme `CodexChatHost`.

- Deterministic diagnostics and repro:

```sh
cd apps/CodexChatApp
swift run CodexChatCLI doctor
swift run CodexChatCLI smoke
swift run CodexChatCLI repro --fixture basic-turn
```

Runtime protocol mismatches (`unknown variant`, `missing field`, `invalid request`) usually indicate an outdated `codex` CLI; update it and retry first.

## CI/CD Policy

- Local-first is required for contributor validation and release readiness.
- GitHub Actions is budget mode and runs hosted quick smoke only (`make quick`).
- Run smoke/reliability/full checks locally before merge.

## Validation Before PR

```sh
make prepush-local
pnpm -s run check
```

## Tests Layout

- Most tests live beside their modules:
  - `apps/CodexChatApp/Tests/CodexChatAppTests`
  - `packages/*/Tests/*`
- Root `tests/` currently stores shared fixtures used by integration/protocol tests.

## Issue Filing Requirements

Include:

- `swift run CodexChatCLI doctor` output (from `apps/CodexChatApp`)
- `swift run CodexChatCLI smoke` output (from `apps/CodexChatApp`)
- deterministic repro fixture (`repro --fixture <name>`) or minimal step list
- whether the issue reproduces in `CodexChatHost`

Issues missing deterministic repro details may be labeled `needs-repro`.

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
