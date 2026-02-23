# Runtime Data Reliability Contract

Date: 2026-02-23
Owner: Team A (Runtime Reliability + Data Foundation)

## Scope

This contract defines non-negotiable runtime and persistence invariants for CodexChat's local-first, two-pane architecture.

Primary implementation surfaces:
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift`
- `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteRuntimeThreadMappingRepository.swift`

## Runtime Lifecycle Invariants

1. Runtime reconnect/restart must reconcile transient state.
- Required behavior: clear stale approval state, clear active turn contexts, reset runtime thread caches, then refresh capabilities/account/model state.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:331`.

2. App-level automatic runtime recovery must be bounded.
- Required behavior: attempt restart on bounded schedule and stop with explicit recoverable error if exhausted.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:394`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:8`.

3. Worker-level recovery must be bounded by consecutive failures.
- Required behavior: non-primary worker restart attempts stop after configured consecutive-failure limit; successful recovery resets consecutive failure count.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:454`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:701`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:37`.

## Runtime Thread Mapping Invariants

1. Local thread to runtime thread mapping must be persisted and rehydrated.
- Evidence: `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteRuntimeThreadMappingRepository.swift:34`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:429`.

2. Stale runtime thread IDs must be detected and retried with a new runtime thread mapping.
- Required behavior: detect stale/missing thread errors, invalidate mapping, recreate runtime thread mapping, retry exactly once.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:164`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:632`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:662`.

## Approval Continuity Invariants

1. Runtime interruption must clear stale approval queue state.
- Required behavior: clear thread-scoped + unscoped approval queues and in-flight decision state on termination, restart, or communication failure.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`.

2. Approval reset must be explicit to the user.
- Required behavior: set explicit status message and append transcript action card (`approval/reset`) when local thread context is known.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:906`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:920`.

## Turn Persistence Invariants

1. Turn start should checkpoint as `pending` before runtime turn execution.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:112`.

2. Checkpoint begin failure must degrade safely.
- Required behavior: log warning and continue runtime turn dispatch instead of silently dropping the turn.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:127`.

3. Completion durability policy:
- Required behavior: failed turns persist with immediate durability; non-failed completions may be batched.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:174`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:177`.

## Archive Durability Invariants

1. Transcript writes must use crash-safe replace strategy.
- Required behavior: write to temp path then `replaceItemAt`/move, removing temporary artifacts on failure.
- Evidence: `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`.

2. Failed checkpoint writes must not corrupt existing transcript.
- Required behavior: failed begin/fail/finalize writes preserve previously committed archive content.
- Evidence: `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:163`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:251`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:299`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:362`.

## Verification Matrix

- Runtime auto-recovery bounds:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:7`
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:40`
- Shared recovery policy parsing and worker bounds:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeRecoveryPolicyTests.swift:4`
- Stale mapping classification + retry bound:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:7`
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:34`
- Approval reset continuity:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`
  - `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306`
- RuntimePool non-primary termination suppression + pin reassignment:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:7`
- RuntimePool non-primary recovery resumes pinned routing after restart:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:82`
- RuntimePool repeated crash/recovery cycles preserve post-recovery routing:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171`
- Worker recovery bound/reset:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:119`
  - `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:129`
- Batcher pressure and spill handling:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101`
- Checkpoint durability + temp cleanup:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`
  - `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:208`
  - `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:299`
  - `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:362`
- Runtime degradation behavior on checkpoint begin failure:
  - `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:339`

## Change Control

Any behavior change affecting invariants above must include:
1. A direct regression test in `apps/CodexChatApp/Tests/CodexChatAppTests/`.
2. Contract update in this file.
3. Planning update in:
- `docs-public/planning/team-a-runtime-foundation-research.md`
- `docs-public/planning/team-a-runtime-foundation-built-vs-next.md`
