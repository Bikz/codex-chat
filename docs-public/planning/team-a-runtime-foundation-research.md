# Team A Runtime Foundation Research

Date: 2026-02-23  
Scope: Runtime reliability + data foundation across `packages/CodexKit/**`, `packages/CodexChatInfra/**`, `packages/CodexChatCore/**`, and Team A-owned app runtime/data files.

Assumption: This assessment is grounded in repository state at commit `8621e63ed6d4ca60dc439be67910e06c60425123`.
Assumption: "Missing" means no direct test or contract statement was found for the exact invariant, even when adjacent behavior is covered.

## 1) Architecture Map

### 1.1 Runtime lifecycle
- Runtime startup and restart flow through `startRuntimeSession()` / `restartRuntimeSession()` and converge in `connectRuntime(restarting:)`.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:253`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:273`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:309`.
- Reconnect reconciles transient runtime state: approval queue reset, active-turn cleanup, thread cache reset, account/model refresh, and prewarm scheduling.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:331`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:329`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:337`.
- App-level automatic recovery uses bounded attempts with env-overridable delays and capped attempt count.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:354`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:397`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:413`.

### 1.2 Turn lifecycle
- `dispatchNow(...)` performs concurrency reservation, thread mapping resolution, checkpoint begin, and runtime turn start.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:88`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:114`.
- Stale runtime thread errors are classified and retried with explicit single-retry policy (`1` max).  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:164`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:640`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:670`.
- Turn completion persistence routes failures to immediate durability and successful turns to batched durability.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:174`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:177`.

### 1.3 Persistence lifecycle
- Metadata is GRDB-backed with migration and repository boundaries (`Core` protocols, `Infra` implementations).  
Evidence: `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9`, `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataRepositories.swift:22`.
- Transcript artifacts use canonical per-thread markdown checkpoints (`pending/completed/failed`) and atomic replace writes.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:98`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:114`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`.
- Completion batching is configurable and bounded (`maxPendingJobs`, `flushThreshold`, timer window).  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:10`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:51`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:60`.

### 1.4 Recovery lifecycle
- Runtime termination and runtime communication errors both reconcile stale approvals and clear runtime caches.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:812`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:824`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`.
- RuntimePool worker recovery now has bounded consecutive-failure attempts and resets failure count after successful recovery.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:8`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:454`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:489`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:710`.

## 2) Capability Inventory (Built / Partial / Missing)

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Local-first managed storage root and structure | Built | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:15`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:43`, `docs-public/ARCHITECTURE_CONTRACT.md:27` | Aligns with local-first ownership constraint. |
| Metadata DB + repository boundary | Built | `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9` | Stable core/infra split. |
| Runtime-thread mapping persistence/hydration | Built | `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteRuntimeThreadMappingRepository.swift:34`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:433` | Includes cache + persisted fallback. |
| Stale runtime-thread recovery policy + retry bound | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:640`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:670`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:34` | Single retry is explicit and tested. |
| Approval continuity reset (termination/error/restart) | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Includes explicit user-facing reset card/message. |
| App-level bounded auto-recovery attempts | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:354`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:413`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:40` | Attempts are now directly asserted in tests. |
| Worker-level bounded restart attempts | Built | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:454`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:703`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:129` | Consecutive-failure cap and recovery reset both tested. |
| Transcript checkpoint durability with atomic replace | Built | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:251` | Write-denial fault tests added for begin/fail/finalize. |
| Completion persistence batching under pressure | Built | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:10`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101` | Max pending spill now directly tested. |
| Runtime/data reliability public contract doc | Missing | `docs-public/ARCHITECTURE_CONTRACT.md:27`, `docs-public/planning/feature-inventory.md:38` | Invariants still spread across multiple docs. |

## 3) Reliability Guarantees Matrix

| Reliability Guarantee | Contract Reference | Implementation Evidence | Test Evidence | Status |
|---|---|---|---|---|
| Startup health validates project/thread and repairs structure | `AGENTS.md:60` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:29`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:412` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:203` | Built |
| Runtime reconnect/restart reconciles transient state | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:331`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Built |
| Stale thread ID recreate + bounded retry | `AGENTS.md:49` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:164`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:670` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153` | Built |
| Approval queue reset with explicit user message on interruption | `AGENTS.md:52` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Built |
| Bounded app-level auto-recovery backoff and terminal failure | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:354`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:413` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:40` | Built |
| Bounded worker-level recovery and failure-count reset | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:454`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:710` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:129` | Built |
| Crash-safe transcript write path | `AGENTS.md:58` | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555` | `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:251` | Built |
| Runtime continues when checkpoint start persistence fails | `AGENTS.md:58` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:114` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:339` | Built |

Assumption: Fault-injection coverage validates write-denial failures, not OS crash-mid-replace simulation.

## 4) Test Coverage Matrix (Code-to-Tests)

| Behavior | Implementation | Test Coverage | Coverage Status |
|---|---|---|---|
| Stale mapping detection/recreate + retry policy | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:640`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:670` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:200` | Strong |
| Approval reset continuity (error + restart paths) | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` | Strong |
| App auto-recovery attempt bounds | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:354`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:413` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeAutoRecoveryTests.swift:40` | Strong |
| Worker restart boundedness/reset policy | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:454`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:710` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:119`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:129` | Medium |
| Checkpoint durability and write-denial handling | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555` | `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:163`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:251` | Strong |
| Runtime behavior under checkpoint begin failure | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:114` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:339` | Medium |
| Batcher pressure handling (threshold/shutdown/max spill) | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:51`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:60` | `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:48`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:74`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101` | Strong |
| RuntimePool non-primary `runtime/terminated` event-flow behavior (pin reassignment + event suppression + restart loop) | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:376`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:448` | No direct event-driven assertion found | Missing |

## 5) Doc Staleness Findings (exact file paths)

1. `docs-public/planning/feature-inventory.md:45` still frames stale mapping recreation as an `Assumption`, but this is now explicit and tested.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:640`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeStaleThreadRecoveryPolicyTests.swift:7`.

2. `docs-public/planning/workstreams.md:14` references prep files (`AppModel+RuntimeState.swift`, `AppModel+UXState.swift`, `AppModel+ExtensibilityState.swift`) that are not present in current tree.  
Evidence: `docs-public/planning/workstreams.md:14`, and no matching files under `apps/CodexChatApp/Sources/CodexChatApp/`.

3. Runtime/data reliability invariants remain fragmented across multiple docs instead of one runtime foundation contract page.  
Evidence: `AGENTS.md:45`, `docs-public/ARCHITECTURE_CONTRACT.md:27`, `docs-public/planning/team-a-runtime-foundation-research.md:1`.

## 6) Refactor Opportunities (ranked by impact and merge risk)

| Rank | Opportunity | Impact | Merge Risk | Evidence |
|---|---|---|---|---|
| 1 | Add event-driven RuntimePool resilience tests for non-primary worker termination flow (degrade, pin reassignment, restart scheduling, event suppression). | High | Medium | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:376`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:448`. |
| 2 | Introduce a shared `RuntimeRecoveryPolicy` value used by AppModel and RuntimePool for backoff/attempt cap semantics. | High | Medium | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:354`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:703`. |
| 3 | Consolidate runtime-thread mapping mutation logic (cache + persistence + pin/unpin) into one internal coordinator surface. | Medium | Medium | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:433`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:601`. |
| 4 | Add deterministic crash-boundary durability harness for transcript atomic replace beyond write-denial faults. | Medium | Low | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`. |
| 5 | Extract protocol compatibility fallback heuristics into a shared policy module with CodexKit coordination. | Medium | Medium | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:689`, `packages/CodexKit/Sources/CodexKit/CodexRuntime+Params.swift:177`. |
