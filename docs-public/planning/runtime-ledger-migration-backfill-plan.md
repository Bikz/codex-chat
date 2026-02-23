# Runtime Ledger Migration and Backfill Plan

Date: 2026-02-23  
Owner: Team A (Runtime Reliability + Data Foundation)

Assumption: Existing canonical thread artifacts remain the source of truth during migration.
Assumption: Migration must be local-first, crash-safe, and resumable.

## Goal

Move from transcript-only durability to an event-sourced reliability ledger without breaking existing thread history or recovery behavior.

## Current State

1. Canonical thread transcript artifacts exist at `<project>/chats/threads/<thread-id>.md`.
2. Replay and ledger export are available through `CodexChatCLI replay` and `CodexChatCLI ledger export`.
3. Marker-based idempotent backfill is available through `CodexChatCLI ledger backfill`.
4. Exported ledger is currently generated from existing archive turns (derived artifact, not authoritative store).

## Target State

1. Runtime and persistence events are durably written as first-class ledger records.
2. Transcript views are derived from ledger events.
3. Recovery, approvals, and dangerous-action context are reconstructable from a single ordered event stream.

## Migration Phases

### Phase A: Dual-write introduction

1. Keep transcript checkpoint/finalization writes unchanged.
2. Add ledger append writes for each persisted turn/action boundary.
3. Validate append ordering and crash-safe atomicity via deterministic tests.

### Phase B: Backfill existing projects

1. Enumerate existing thread archives in project storage.
2. Generate ledger files idempotently from archive turns.
3. Write migration marker per thread when backfill succeeds.
4. On rerun, skip threads with completed markers unless explicit force flag is passed.

Status: Implemented (CLI path) for deterministic local backfill with marker files under
`<project>/chats/threads/.ledger-backfill/`.

### Phase C: Read-path cutover

1. Prefer ledger-first replay/read paths when ledger exists and passes schema validation.
2. Fall back to transcript archive parsing when ledger is absent or invalid.
3. Emit explicit diagnostics when fallback is used.

### Phase D: Contract hardening

1. Publish ledger schema contract version and compatibility matrix.
2. Add tooling for schema validation and upgrade advisories.
3. Document recovery semantics for partially migrated projects.

## Safety Requirements

1. No destructive rewrite of existing transcript artifacts during migration.
2. Every migration step must be restart-safe and idempotent.
3. Migration markers must be written atomically.
4. Any ledger parse failure must degrade to known-safe transcript read behavior.

## Test Plan

1. Unit tests for backfill idempotency and marker semantics.
2. Crash-boundary tests for dual-write ordering and partial-write cleanup.
3. Fixture tests covering mixed states:
- transcript-only thread
- ledger + transcript thread
- partially migrated thread with interrupted marker write

## Exit Criteria

1. Backfill runs deterministically on local harness across representative fixtures.
2. Replay parity checks pass between transcript-derived and ledger-derived summaries.
3. Migration status is observable via CLI diagnostics and reliability bundle artifacts.

## Evidence (Current Branch)

1. Backfill command parser and CLI surface:
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatCLICommandParser.swift`
- `apps/CodexChatApp/Sources/CodexChatCLI/main.swift`

2. Backfill implementation and marker schema:
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatRuntimeReliabilityArtifacts.swift`

3. Backfill idempotency + force regression test:
- `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatRuntimeReliabilityArtifactsTests.swift`
