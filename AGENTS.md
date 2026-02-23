# CodexChat Engineering Contract

This file is the operating contract for all contributors (human and AI).
The bar is production-quality, reliability-first software.

## Product Contract
- Build CodexChat as a macOS-native, two-pane product:
  1) sidebar (projects + threads)
  2) conversation canvas
- Do not ship a persistent third pane in current releases.
- Keep conversation primary. Use inline cards, sheets, and bottom drawers for auxiliary workflows.
- Prioritize local-first ownership, legible actions, and safe agent power escalation.

## Source Of Truth
1. `AGENTS.md`
2. `README.md`
3. `docs-public/` (tracked docs)
4. private `docs/` (local planning memory, ignored by git)
5. code reality

## Non-Negotiables
- Keep build and tests green before finishing work.
- Work one epic/fix scope at a time.
- Ship empty/loading/error states for user-facing surfaces.
- Accessibility is mandatory: keyboard navigation, focus visibility, semantic labels, contrast.
- Never log secrets or auth material.
- Never introduce a persistent third pane.

## Delivery Loop
1. Clarify acceptance criteria and affected user journey.
2. Implement in small increments.
3. Run fast checks (`make quick`), contributor smoke checks (`make oss-smoke`), then full checks (`pnpm -s run check`).
4. Add/adjust tests for changed behavior.
5. Update docs when behavior, architecture, or ops guidance changes.
6. Commit atomically with clear scope in the message.

## Architecture Standards
- Keep modules focused (`apps/`, `packages/` boundaries must remain clear).
- `apps/CodexChatHost` is the canonical GUI entrypoint and release source.
- `apps/CodexChatApp` houses `CodexChatShared` behavior and `CodexChatCLI` contributor tooling.
- Prefer explicit data flow and small composable types over opaque abstraction layers.
- Store app metadata in Infra repositories; keep UI logic in app layer.
- Preserve two-pane IA and established design-system patterns.

## Reliability Standards
- Detailed invariant reference: `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md`
- Runtime resilience:
  - Automatic runtime recovery must use bounded backoff.
  - Runtime reconnect/restart must reconcile transient state (turns, approvals, thread caches).
- Runtime thread mapping:
  - Persist and rehydrate local-thread to runtime-thread mappings.
  - Detect stale runtime thread IDs and recreate/retry once safely.
- Approval continuity:
  - If runtime is interrupted, clear stale in-memory approval queue.
  - Show explicit user-facing reset messaging and transcript action card when context is known.
- Login continuity:
  - Pending browser login sessions must be cancellable.
  - Cancel in-flight login on teardown and when switching auth flows.
- File durability:
  - Use crash-safe writes (atomic replace / temp-file strategy) for user artifacts and archives.
- Startup health:
  - Validate selected project/thread on launch.
  - Handle moved/deleted project paths gracefully.
  - Re-bootstrap required project folder structure for healthy projects.

## Security And Safety
- API keys belong in macOS Keychain only.
- Diagnostics and logs must be non-sensitive by default.
- Treat web/network outputs as untrusted inputs.
- Maintain explicit guardrails and confirmations for dangerous modes.

## Code Quality Rules
- Keep the repo steerable:
  - when a Swift file exceeds ~500 LOC, split into focused types/extensions.
- Prefer straightforward, testable logic over over-engineering.
- Keep comments minimal and high-signal.
- Preserve naming consistency and module boundaries.

## Testing Requirements
- Every bug fix requires a regression test when feasible.
- Core deterministic logic must have unit tests.
- Runtime protocol, approval flows, and persistence paths need explicit coverage.
- Use deterministic fixtures for smoke/integration paths.
- Keep the fast loop fast (`make quick` under ~60s target on a normal dev machine).

## Documentation Rules
- `docs/` is private and untracked by design. Do not add tracked files there.
- Put contributor-facing docs in `docs-public/`.
- Add or update ADRs for:
  - architecture/data-flow changes
  - schema/migration changes
  - major dependency shifts
  - auth/safety semantic changes

## Git And Collaboration
- Atomically commit.
- Use small atomic commits.
- Do not rewrite unrelated changes.
- Do not use destructive git commands unless explicitly requested.
- If unrelated breakage blocks progress, report the blocker with exact file and reason.

## Definition Of Done
- Acceptance criteria met.
- No regression in core journeys.
- Tests updated and passing.
- Docs/ADRs updated where needed.
- UX states and accessibility considerations included.
