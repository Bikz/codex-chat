# Team A Runtime Foundation: Built vs Next

Date: 2026-02-23  
Scope: Runtime reliability + data foundation planning for CodexChat’s two-pane, local-first product constraints.

Assumption: Prioritization below optimizes for reliability risk reduction and merge safety, not net-new feature breadth.

## 1) What Is Already Built

| Area | Already Built | Evidence |
|---|---|---|
| Local-first storage foundation | Managed root with explicit `projects/global/system` layout and required subfolders. | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:15`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:23`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:43`, `docs-public/ARCHITECTURE_CONTRACT.md:27` |
| Metadata data layer | GRDB metadata database with versioned migrations and repository composition. | `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataRepositories.swift:22`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9` |
| Runtime-thread mapping persistence | Runtime thread IDs are persisted, rehydrated, and reverse-resolved through repository. | `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteRuntimeThreadMappingRepository.swift:34`, `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteRuntimeThreadMappingRepository.swift:53` |
| Turn dispatch reliability path | Dispatch reserves concurrency, checkpoints transcript, then starts runtime turn with compatibility fallback behavior. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:88`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:114`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:644` |
| Stale mapping recovery | On likely stale-thread errors, mapping is invalidated, recreated, and retried in-place. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:157`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:601`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153` |
| Runtime reconnect state reconciliation | Restart/connect reconciles approvals, active turns, runtime caches, model/account state. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:325`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:328`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:329` |
| App-level runtime auto-recovery | Unexpected runtime termination schedules bounded auto-restart attempts `[1,2,4,8]`. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:384` |
| Approval continuity and explicit reset UX | Pending approvals are cleared on runtime interruptions with warning message + transcript action card. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:856`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:874`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:874` |
| Transcript durability pattern | Checkpoint states (`pending/completed/failed`) + atomic replace writes + legacy archive backfill path. | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:114`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:333` |
| Completion persistence batching | Turn completions are batched for throughput; failures flush immediately. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:174`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:39`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:32` |
| Startup health repair | Launch validates project paths, repairs folder structure, and clears stale selected thread IDs. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:29`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:90`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:203` |
| Storage migration durability | Managed-root migration rewrites metadata paths and syncs SQLite + WAL/SHM sidecars. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:137`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:347`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:366` |

## 2) What Must Be Built Next (Prioritized Backlog)

### P0 (Reliability invariants to lock first)

1. Add explicit tests for app-level auto-recovery attempt bounds and terminal failure messaging.
Evidence of current gap: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352` has bounded attempts, while current smoke test checks eventual reconnect only (`apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:292`).

2. Add RuntimePool worker-failure resilience tests (degrade, pin reassignment, restart retry behavior).
Evidence of current gap: restart logic exists in `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:376` and `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:440`, but `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:5` currently focuses on ID routing/selection helpers.

3. Add fault-injection durability tests for transcript atomic replace failure and partial-write scenarios.
Evidence of current gap: atomic write path in `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`; current checkpoint tests validate state transitions but not injected file-system failures (`apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:7`).

4. Publish a dedicated runtime/data reliability contract doc (RuntimePool routing rules, thread-mapping invariants, recovery policies).
Evidence of current gap: runtime reliability details are spread across `AGENTS.md:45`, `docs-public/ARCHITECTURE_CONTRACT.md:27`, and planning docs, without a single runtime contract page.

### P1 (Policy consistency and maintainability)

1. Consolidate recovery policy (attempt limits/backoff schedule) across AppModel and RuntimePool to avoid drift.
Evidence: app-level schedule in `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`; worker-level restart schedule in `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:446`.

2. Consolidate failure classification logic used in turn completion handling and persistence.
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:591` and `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimePersistence.swift:20`.

3. Update planning docs to remove stale "Assumption" labels where behavior is now explicit and tested.
Evidence: `docs-public/planning/feature-inventory.md:45` vs explicit runtime behavior/tests at `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:157` and `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153`.

### P2 (Throughput and observability hardening)

1. Add deterministic load tests for long-running RuntimePool worker degradation/recovery loops.
Evidence base to extend: `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolLoadHarnessTests.swift:11`.

2. Add targeted metrics/assertions around follow-up auto-drain starvation across many active threads.
Evidence path: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400`.

3. Add explicit contributor-facing runbook for codex-home normalization and quarantine recovery interpretation.
Evidence path: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:292`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:180`.

## 3) 30/60/90 Day Roadmap

### Day 0-30 (Stabilize invariants)

1. Ship P0 tests for backoff bounds, worker recovery, and transcript write fault paths.
2. Create runtime/data reliability contract doc in `docs-public/`.
3. Gate merges on new reliability suite in `make quick` where practical.

Dependencies:
- Existing harnesses: `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:292`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolLoadHarnessTests.swift:11`.
- Existing persistence seams: `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:4`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`.

### Day 31-60 (Unify policy and reduce drift)

1. Refactor to shared recovery policy object and shared turn-failure classifier.
2. Expand test assertions to enforce identical behavior before/after refactor.
3. Update planning docs for assumption cleanup and ownership reality.

Dependencies:
- P0 tests in place to guard behavior.
- Contract doc accepted so refactors target explicit invariants.

### Day 61-90 (Scale and operational readiness)

1. Extend RuntimePool load harness into repeated-failure soak scenarios.
2. Add follow-up auto-drain fairness/starvation stress tests.
3. Publish storage-repair operator runbook and troubleshooting checklist.

Dependencies:
- P1 policy unification completed.
- CI runtime/load jobs available for longer-running suites.

Assumption: 90-day slices assume Team A retains ownership of `packages/CodexKit/**`, `packages/CodexChatInfra/**`, `packages/CodexChatCore/**`, and runtime/data app model files per `docs-public/planning/workstreams.md:35`.

## 4) Proposed Contract Changes and Migration Considerations

### Proposed contract changes

1. Clarify bounded-recovery scope:
- Add explicit wording that both app-level runtime recovery and RuntimePool worker recovery must have bounded attempts, not only bounded delay intervals.
- Evidence driving change: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352` (bounded attempts) vs `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:480` (retries continue).

2. Add runtime/data invariants section to public docs:
- Define canonical invariants for thread mapping, approval reset behavior, checkpoint semantics, and restart reconciliation.
- Evidence driving change: invariants are currently implemented but fragmented across code/docs (`AGENTS.md:45`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:390`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`).

3. Document codex-home normalization safety boundary as runtime-cache-only quarantine:
- Reinforce distinction between user-owned project transcripts and quarantined runtime internals.
- Evidence driving change: `docs-public/ARCHITECTURE_CONTRACT.md:76`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:67`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:156`.

### Migration considerations

1. Schema migrations:
- No immediate SQLite schema migration required for P0/P1 test and policy-doc work.
- If restart-attempt counters are later persisted, add a dedicated migration in `MetadataDatabase` and backfill defaults.

2. Behavior migrations:
- If worker-restart attempts become capped, include explicit user-facing state transition when cap is reached (parallel to existing app-level message).
- Reference message pattern: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:384`.

3. Data durability:
- No transcript format migration required if checkpoint marker syntax remains unchanged.
- Existing canonical + legacy backfill compatibility should remain stable (`apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:210`).

