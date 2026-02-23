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
| Stale runtime-thread recovery policy | Detection + recreate logic is explicit and bounded to one retry. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:640`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:670`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:34` |
| App-level auto-recovery boundedness | Backoff attempts are bounded, env-configurable, and capped in implementation and tests. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:354`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:413`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:40` |
| Worker-level recovery boundedness | RuntimePool has consecutive failure cap and reset-on-recovery semantics. | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:454`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:710`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:129` |
| Approval continuity | Pending approvals reset with explicit UX messaging on communication failure and restart. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` |
| Transcript durability | Checkpoint phases and atomic write path with fault-injection tests for write-denial failures. | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207` |
| Runtime degradation explicitness | Turn-start checkpoint failures log explicit warning while runtime turn still starts. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:114`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:339` |
| Completion persistence pressure handling | Batcher threshold, shutdown, and max-pending spill are now tested. | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:10`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101` |
| Runtime option compatibility fallback | Retry-without-turn-options heuristics are codified and directly tested. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:689`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeTurnOptionsFallbackTests.swift:7` |
| Runtime/data reliability contract | Dedicated runtime/data invariants contract is now published and linked from architecture docs. | `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md:1`, `docs-public/ARCHITECTURE_CONTRACT.md:3` |

## 2) What Must Be Built Next (Prioritized Backlog)

### P0

1. Add crash-boundary durability harness beyond write-denial fault injection for transcript replace semantics.
Evidence gap: current tests validate permission/write-denial failure, not simulated crash-mid-replace semantics (`apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`).

2. Expand RuntimePool resilience coverage from single non-primary termination regression to repeated degradation/recovery soak coverage.
Evidence gap: deterministic load harness exists but does not repeatedly assert worker degradation/recovery invariants (`apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolLoadHarnessTests.swift:11`).

### P1

1. Introduce shared `RuntimeRecoveryPolicy` used by AppModel and RuntimePool to prevent policy drift.
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:354` and `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:703` currently encode policy in separate places.

2. Consolidate runtime-thread mapping updates (cache + repo + pin/unpin) into one internal coordinator path.
Evidence: mapping mutations are spread in `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:433`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:601`.

3. Remove stale assumption markers in planning docs now that reliability behavior is explicit and tested.
Evidence: `docs-public/planning/feature-inventory.md:45`.

### P2

1. Extend RuntimePool load harness into repeated degradation/recovery soak tests.
Evidence seed: `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolLoadHarnessTests.swift:11`.

2. Add fairness/starvation tests for follow-up auto-drain under high thread fan-out.
Evidence seed: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400`.

3. Publish operator runbook for codex-home normalization/quarantine interpretation.
Evidence seed: `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:156`.

## 3) 30/60/90 Day Roadmap Slices

### Day 0-30

1. Add crash-boundary transcript durability harness design and first deterministic checks.
2. Extend RuntimePool resilience into repeated degradation/recovery soak assertions.
3. Link runtime/data reliability contract from additional contributor docs (`AGENTS.md` and planning indexes).

Dependencies:
- Existing RuntimePool + harness infrastructure: `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:376`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolLoadHarnessTests.swift:11`.
- Existing transcript write seam: `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`.

### Day 31-60

1. Implement shared `RuntimeRecoveryPolicy` and migrate AppModel + RuntimePool callers.
2. Add regression tests that pin current behavior before/after migration.
3. Consolidate mapping mutation paths and keep behavior fixed via smoke tests.

Dependencies:
- P0 test baselines in place to guard refactor behavior.
- Runtime/data reliability contract merged to anchor acceptance criteria.

### Day 61-90

1. Add long-running RuntimePool recovery soak in CI optional lane.
2. Add follow-up queue fairness load tests.
3. Publish storage-repair operator runbook with concrete troubleshooting flows.

Dependencies:
- Day 31-60 policy consolidation complete.
- CI budget allocated for longer-running reliability jobs.

## 4) Proposed Contract Changes and Migration Considerations

### Proposed contract changes

1. Adopt the new runtime/data reliability contract as the canonical invariant reference from contributor-facing docs (`AGENTS.md`, planning indexes).

2. Continue updating planning docs to remove stale assumption markers where behavior is now explicit and tested.

3. Clarify that bounded recovery applies at both app runtime layer and RuntimePool worker layer, with shared policy terminology.

### Migration considerations

1. Data migration:
- No SQLite schema migration is required for the changes landed in this slice.

2. Behavior migration:
- If `RuntimeRecoveryPolicy` is introduced, roll out behind equivalent tests to preserve current retry/backoff semantics.

3. Documentation migration:
- Add links from `AGENTS.md` and planning index docs to `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md` to prevent future drift.

Assumption: No UI IA migration is required because all changes stay inside existing two-pane surfaces and explicit messaging paths.
