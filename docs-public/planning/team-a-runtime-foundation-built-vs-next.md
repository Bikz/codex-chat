# Team A Runtime Foundation: Built vs Next

Date: 2026-02-23  
Scope: Runtime reliability + data foundation planning for CodexChat’s macOS-native, two-pane, local-first constraints.

Assumption: Priorities below optimize for reliability risk reduction and merge safety before feature breadth.
Assumption: P0 means "blocks confidence in runtime/data invariants under failure," not "customer-visible feature gap."

## 1) What Is Already Built

| Area | Already Built | Evidence |
|---|---|---|
| Local-first storage foundation | Managed root with explicit `projects/global/system` boundaries and required structure. | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:15`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:43`, `docs-public/ARCHITECTURE_CONTRACT.md:27` |
| Metadata durability foundation | GRDB metadata migrations and repository boundary split across Core/Infra. | `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9`, `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataRepositories.swift:22` |
| Shared runtime recovery policy | App-level and worker-level recovery semantics now use a shared policy module and dedicated tests. | `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:3`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:394`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:697`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeRecoveryPolicyTests.swift:4` |
| Stale runtime-thread recovery policy | Detection + recreate logic is explicit and bounded to one retry. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:632`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:662`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:34` |
| Runtime-thread mapping mutation consolidation | Cache/reverse-map/pin mutation now routes through shared internal helper paths. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:400`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:517`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:620` |
| App-level auto-recovery boundedness | Backoff attempts are bounded, env-configurable, and capped in implementation and tests. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:394`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:40` |
| Worker-level recovery boundedness | RuntimePool has consecutive-failure cap and reset-on-recovery semantics. | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:454`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:701`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:129` |
| RuntimePool repeated degradation/recovery coverage | Non-primary worker crash/restart behavior is tested across repeated cycles and post-recovery routing. | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171` |
| Approval continuity | Pending approvals reset with explicit UX messaging on communication failure and restart. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` |
| Transcript durability | Checkpoint phases and atomic write path with fault-injection tests for write-denial failures and crash-leftover temp artifacts. | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:362` |
| Completion persistence pressure handling | Batcher threshold, shutdown, and max-pending spill are directly tested. | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:10`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101` |
| Runtime option compatibility fallback | Retry-without-turn-options heuristics are codified and directly tested. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:671`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeTurnOptionsFallbackTests.swift:7` |
| Runtime/data reliability contract | Dedicated runtime/data invariants contract is published and cross-linked from architecture and contributor docs. | `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md:1`, `docs-public/ARCHITECTURE_CONTRACT.md:4`, `AGENTS.md:46` |

## 2) What Must Be Built Next (Prioritized Backlog)

### P0

1. Add deterministic crash-boundary durability harness for transcript writes around `replaceItemAt`.
Evidence gap: current tests cover permission denial and stale temp artifacts, but do not simulate abrupt interruption during the replacement boundary (`apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`).

### P1

1. Add fairness/starvation regression coverage for follow-up auto-drain under high thread fan-out.
Evidence gap: follow-up logic exists, but targeted high-fan-out fairness tests are missing (`apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400`).

2. Publish storage repair operator runbook for codex-home normalization/quarantine outcomes.
Evidence gap: repair logic is implemented, but there is no dedicated troubleshooting runbook (`apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:156`).

3. Reconcile `workstreams.md` ownership language with active multi-agent collaboration contract.
Evidence gap: stream ownership is documented as exclusive in places that conflict with current shared-worktree process (`docs-public/planning/workstreams.md:39`, `AGENTS.md:92`).

### P2

1. Add optional longer-running RuntimePool recovery soak lane in CI once budget is allocated.
Evidence seed: deterministic resilience fixtures now exist (`apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171`).

2. Extract runtime compatibility fallback heuristics into a shared policy seam with CodexKit alignment.
Evidence seed: fallback behavior currently lives in app layer dispatch path (`apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:671`).

## 3) 30/60/90 Day Roadmap Slices

### Day 0-30

1. Land deterministic crash-boundary harness for transcript replacement path.
2. Add first pass follow-up fairness/starvation load tests.
3. Update `workstreams.md` ownership language and stale prep-file references.

Dependencies:
- Existing transcript write seam and checkpoint tests: `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`.
- Existing follow-up scheduler flow: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400`.

### Day 31-60

1. Publish codex-home normalization/quarantine operator runbook.
2. Fold follow-up fairness tests into standard reliability suite.
3. Add shared acceptance criteria snippets to planning docs referencing reliability contract.

Dependencies:
- P0 crash-boundary baseline in place.
- Reliability contract remains canonical (`docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md:1`).

### Day 61-90

1. Add optional long-running RuntimePool soak lane to CI.
2. Start policy-seam extraction for runtime compatibility fallback.
3. Re-review reliability matrix against production incident learnings.

Dependencies:
- Day 0-60 reliability baselines stabilized.
- CI budget allocated for longer-running reliability jobs.

## 4) Proposed Contract Changes and Migration Considerations

### Proposed contract changes

1. Clarify in reliability contract language that bounded recovery policy is now shared by app-level and worker-level recovery paths.

2. Add an explicit contract note for follow-up queue fairness expectations once tests are landed.

3. Update planning docs to align workstream ownership language with the active multi-agent shared-worktree process.

### Migration considerations

1. Data migration:
- No SQLite schema migration is required for the changes landed in this slice.

2. Behavior migration:
- Shared recovery policy has already been introduced behind existing regression tests; preserve current delay/attempt semantics while extending coverage.

3. Documentation migration:
- Keep `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md` as the canonical invariant source and ensure planning docs link back to it for future updates.

Assumption: No UI IA migration is required because all changes stay inside existing two-pane surfaces and explicit messaging paths.
