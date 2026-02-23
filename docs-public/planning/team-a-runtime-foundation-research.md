# Team A Runtime Foundation Research

Date: 2026-02-23  
Scope: Runtime reliability + data foundation across `packages/CodexKit/**`, `packages/CodexChatInfra/**`, `packages/CodexChatCore/**`, and Team A-owned app runtime/data files.

Assumption: This assessment is grounded in repository state at commit `d948df692d0e4be5f5060288c6fd3ec0685f34af`.
Assumption: "Missing" means no direct test or contract statement was found for the exact invariant, even when adjacent behavior is covered.

## 1) Architecture Map

### 1.1 Runtime lifecycle
- Runtime startup and restart flow through `startRuntimeSession()` / `restartRuntimeSession()` and converge in `connectRuntime(restarting:)`.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:253`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:273`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:309`.
- Reconnect reconciles transient runtime state: approval queue reset, active-turn cleanup, thread cache reset, account/model refresh, and prewarm scheduling.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:331`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:338`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:341`.
- Recovery policy semantics are centralized and shared across app-level and worker-level recovery paths.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:3`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:394`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:697`.

### 1.2 Turn lifecycle
- `dispatchNow(...)` performs concurrency reservation, thread mapping resolution, checkpoint begin, and runtime turn start.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:86`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:112`.
- Stale runtime thread errors are classified and retried with explicit single-retry policy (`1` max).  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:164`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:632`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:662`.
- Runtime-thread mapping cache + pin/unpin mutation paths are now funneled through shared internal helpers.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:400`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:416`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:424`.

### 1.3 Persistence lifecycle
- Metadata is GRDB-backed with migration and repository boundaries (`Core` protocols, `Infra` implementations).  
Evidence: `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9`, `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataRepositories.swift:22`.
- Transcript artifacts use canonical per-thread markdown checkpoints (`pending/completed/failed`) and atomic replace writes.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:98`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`.
- Completion batching is configurable and bounded (`maxPendingJobs`, `flushThreshold`, timer window).  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:10`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:51`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:60`.

### 1.4 Recovery lifecycle
- Runtime termination and runtime communication errors both reconcile stale approvals and clear runtime caches.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:812`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:824`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`.
- RuntimePool worker recovery has bounded consecutive-failure attempts and resets failure count after successful recovery.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:448`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:489`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:701`.
- Repeated crash/recovery cycles on non-primary workers are now covered by deterministic regression tests.  
Evidence: `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171`.

## 2) Capability Inventory (Built / Partial / Missing)

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Local-first managed storage root and structure | Built | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:15`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:43`, `docs-public/ARCHITECTURE_CONTRACT.md:27` | Aligns with local-first ownership constraint. |
| Metadata DB + repository boundary | Built | `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9` | Stable core/infra split. |
| Shared runtime recovery policy (app + worker layer) | Built | `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:3`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:394`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:697`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeRecoveryPolicyTests.swift:4` | Eliminates policy drift between layers. |
| Runtime-thread mapping persistence/hydration + centralized mutation helpers | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:400`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:429`, `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteRuntimeThreadMappingRepository.swift:34` | Cache + reverse map + pin behavior now routed through shared helper paths. |
| Stale runtime-thread recovery policy + retry bound | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:632`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:662`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:34` | Single retry is explicit and tested. |
| Approval continuity reset (termination/error/restart) | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Includes explicit user-facing reset card/message. |
| App-level bounded auto-recovery attempts | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:394`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:40` | Attempts are directly asserted and capped. |
| Worker-level bounded restart attempts + repeated crash-cycle coverage | Built | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:448`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:701`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171` | Includes repeated non-primary crash/recovery cycle validation. |
| Transcript checkpoint durability with atomic replace | Partial | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:362` | Strong write-denial + temp-artifact cleanup coverage, but no deterministic mid-`replaceItemAt` crash harness yet. |
| Completion persistence batching under pressure | Built | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:10`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101` | Threshold, shutdown flush, and max-pending spill are tested. |
| Follow-up queue fairness under high fan-out | Missing | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400` | Functional behavior exists; starvation/fairness load tests are still missing. |

## 3) Reliability Guarantees Matrix

| Reliability Guarantee | Contract Reference | Implementation Evidence | Test Evidence | Status |
|---|---|---|---|---|
| Startup health validates project/thread and repairs structure | `AGENTS.md:60` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:29`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:412` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:203` | Built |
| Runtime reconnect/restart reconciles transient state | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:331`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Built |
| Stale thread ID recreate + bounded retry | `AGENTS.md:49` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:164`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:662` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153` | Built |
| Approval queue reset with explicit user message on interruption | `AGENTS.md:52` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Built |
| Bounded app-level auto-recovery backoff and terminal failure | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:394`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:8` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeRecoveryPolicyTests.swift:20` | Built |
| Bounded worker-level recovery and failure-count reset | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:448`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:701`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:37` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:129`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeRecoveryPolicyTests.swift:43` | Built |
| Worker recovery remains stable across repeated crash/recovery cycles | `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md:17` | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:448` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171` | Built |
| Crash-safe transcript write path | `AGENTS.md:58` | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555` | `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:362` | Partial |
| Runtime continues when checkpoint start persistence fails | `AGENTS.md:58` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:112` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:339` | Built |

Assumption: Fault-injection coverage validates write-denial failures and crash-leftover artifacts, not OS crash-mid-`replaceItemAt` simulation.

## 4) Test Coverage Matrix (Code-to-Tests)

| Behavior | Implementation | Test Coverage | Coverage Status |
|---|---|---|---|
| Stale mapping detection/recreate + retry policy | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:632`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:662` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:200` | Strong |
| Thread-mapping cache/pin mutation centralization | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:400`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:517`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:620` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:200`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:232` | Medium |
| Approval reset continuity (error + restart paths) | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Strong |
| Shared runtime recovery policy parsing + bounds | `apps/CodexChatApp/Sources/CodexChatApp/RuntimeRecoveryPolicy.swift:8`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:697` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeRecoveryPolicyTests.swift:4`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:116`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:7` | Strong |
| RuntimePool non-primary termination handling + repeated crash/recovery cycles | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:376`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:448` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171` | Strong |
| Checkpoint durability and write-denial handling | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555` | `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:163`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:362` | Strong |
| Batcher pressure handling (threshold/shutdown/max spill) | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:51`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:60` | `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:48`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:74`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101` | Strong |
| Follow-up auto-drain fairness under high fan-out | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400` | No targeted fairness/starvation load tests found. | Missing |

## 5) Doc Staleness Findings (exact file paths)

1. `docs-public/planning/workstreams.md:14` references prep files (`AppModel+RuntimeState.swift`, `AppModel+UXState.swift`, `AppModel+ExtensibilityState.swift`) that are not present in current tree.  
Evidence: `docs-public/planning/workstreams.md:14`, plus no matching files under `apps/CodexChatApp/Sources/CodexChatApp/`.

2. `docs-public/planning/workstreams.md:39` still lists `RuntimePool.swift` and companion files as exclusively owned by Workstream 1, but current multi-agent workflow is shared by design.  
Evidence: `docs-public/planning/workstreams.md:39`, `AGENTS.md:92`.

## 6) Refactor Opportunities (ranked by impact and merge risk)

| Rank | Opportunity | Impact | Merge Risk | Evidence |
|---|---|---|---|---|
| 1 | Add deterministic crash-boundary durability harness for transcript atomic replace beyond write-denial faults. | High | Medium | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`. |
| 2 | Extend follow-up queue tests with fairness/starvation coverage under high thread fan-out. | Medium | Low | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400`. |
| 3 | Publish an operator runbook for codex-home normalization/quarantine interpretation and recovery actions. | Medium | Low | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:156`. |
| 4 | Extract runtime protocol compatibility fallback heuristics into a shared policy seam with CodexKit alignment. | Medium | Medium | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:671`, `packages/CodexKit/Sources/CodexKit/CodexRuntime+Params.swift:177`. |
