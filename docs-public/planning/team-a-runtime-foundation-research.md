# Team A Runtime Foundation Research

Date: 2026-02-23  
Scope: Runtime reliability + data foundation across `packages/CodexKit/**`, `packages/CodexChatInfra/**`, `packages/CodexChatCore/**`, and Team A-owned runtime/data app model files.

Assumption: This assessment is grounded in repository state at commit `ebcacee76d4110ea419a7ad9383537c72f490c78`.
Assumption: Negative claims (for example, "missing test") mean no direct assertion was found in the inspected test files, not that no indirect coverage exists.

## 1) Architecture Map

### 1.1 Runtime lifecycle
- Runtime session start/restart flows through `startRuntimeSession()` and `restartRuntimeSession()`, both funneled into `connectRuntime(restarting:)`.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:253`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:273`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:309`.
- Runtime reconnect reconciles transient state: clears approvals, clears active turns, resets runtime thread caches, refreshes account/model data, then re-prewarms threads.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:325`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:328`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:329`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:337`.
- Runtime event ingestion is async-stream based (`runtimePool.events()`), then batched/coalesced before UI application.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:296`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimeEventDispatchBridge.swift:20`, `apps/CodexChatApp/Sources/CodexChatApp/ConversationUpdateScheduler.swift:40`.

### 1.2 Turn lifecycle
- `dispatchNow(...)` handles message append, concurrency reservation, runtime-thread resolution, checkpoint begin, and runtime turn start.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:34`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:88`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:91`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:114`.
- On stale runtime-thread errors, mapping is invalidated, recreated, and turn start is retried once in the same dispatch flow.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:157`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:162`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:173`.
- On completion, active context is removed and completion persistence is enqueued with immediate durability for failures and batched durability otherwise.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:136`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:174`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:177`.

### 1.3 Persistence lifecycle
- Storage root defaults to `~/CodexChat` and enforces explicit `projects/global/system` structure.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:88`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:15`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:23`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:43`.
- Metadata uses GRDB migrations and strongly-typed repositories with Core protocol boundaries and Infra implementations.  
Evidence: `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:4`, `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9`, `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataRepositories.swift:22`.
- Canonical transcript persistence is thread-scoped markdown with checkpoint phases (`pending`, `completed`, `failed`) and atomic replace writes.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:4`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:98`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`.

### 1.4 Recovery lifecycle
- App-level unexpected runtime termination triggers error state + bounded auto-recovery schedule `[1,2,4,8]`.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:773`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`.
- Worker-level pool recovery uses per-worker restart with exponential backoff and pin reassignment away from failed workers.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:391`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:416`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:440`.
- Storage repair flow can quarantine stale codex-home runtime internals and restart runtime after normalization.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:260`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:273`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:127`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:156`.

## 2) Capability Inventory (Built / Partial / Missing)

| Capability | Status | Evidence | Notes |
|---|---|---|---|
| Local-first managed storage root and folder structure | Built | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:88`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:103`, `docs-public/ARCHITECTURE_CONTRACT.md:27` | Matches product local-first constraints. |
| Metadata DB schema + repository abstraction boundary | Built | `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:9`, `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataRepositories.swift:22` | Clear Core protocol / Infra impl split. |
| Runtime-thread mapping persistence and hydration | Built | `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteRuntimeThreadMappingRepository.swift:34`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:433`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:446` | Includes in-memory cache + persisted fallback. |
| Stale runtime-thread recreation + retry | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:157`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:161`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:173`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153` | Explicit one-path retry on stale indicators. |
| Approval continuity reset on runtime interruption | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:849`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:874`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:874` | Includes explicit user message + transcript action card. |
| App-level bounded runtime auto-recovery | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:384`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:292` | Bounded attempts at app-session level. |
| Worker-level restart policy boundedness | Partial | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:446`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:480` | Backoff interval is capped, but restart attempts are not capped. |
| Checkpointed transcript durability with atomic writes | Built | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:7` | Pending/completed/failed checkpoint semantics exist. |
| Batched completion persistence with failure fast-path | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:174`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:39`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:32` | Failures bypass batching (`.immediate`). |
| Startup project/thread health validation and repair | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Lifecycle.swift:109`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:29`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:203` | Handles missing paths, stale thread selection, folder rebootstrap. |
| Storage root migration with SQLite sidecar sync | Built | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:120`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:347`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:366` | Copies DB + WAL/SHM sidecars for durability. |
| Runtime/data foundation public contract doc depth | Missing | `docs-public/ARCHITECTURE_CONTRACT.md:27`, `docs-public/planning/feature-inventory.md:38` | High-level docs exist, but there is no dedicated RuntimePool/thread-mapping invariants contract document. |

## 3) Reliability Guarantees Matrix

| Reliability Guarantee | Contract Reference | Implementation Evidence | Test Evidence | Status |
|---|---|---|---|---|
| Startup health validates selected project/thread and repairs folders | `AGENTS.md:60` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:29`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Projects.swift:412` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:203` | Built |
| Runtime reconnect/restart reconciles transient turns/approvals/cache | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:325`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:328`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:329` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:874` | Built |
| Stale runtime thread ID detect + recreate + retry once | `AGENTS.md:49` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:157`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:614` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:200` | Built |
| Approval continuity reset with explicit user-facing messaging | `AGENTS.md:52` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:856`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:866`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:874` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:874` | Built |
| Bounded backoff for runtime auto recovery | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:292` (recovery observed, schedule bounds not asserted) | Partial |
| Crash-safe write path for user transcript artifacts | `AGENTS.md:58` | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:563` | `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:7` | Built |
| Metadata durability during storage migration (DB + sidecars) | `AGENTS.md:58` | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:347`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:366` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatStorageMigrationCoordinatorTests.swift:86` | Built |
| Worker-level self-healing boundedness clarity | `AGENTS.md:46` | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:440`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:480` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:5` (scope/id tests only) | Partial |

Assumption: Contract-level "bounded backoff" applies to both app-level and worker-level recoveries; current code clearly bounds delays in both places but only app-level attempts are strictly bounded.

## 4) Test Coverage Matrix (Code-to-Tests)

| Behavior | Implementation | Test Coverage | Coverage Status |
|---|---|---|---|
| Runtime-thread mapping persistence + stale mapping migration | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:433`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:514` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:180`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:200` | Strong |
| Approval fallback + reset semantics | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:386`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:849` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalFallbackTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:874` | Strong |
| Runtime auto recovery on termination | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:348` | `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:292` | Medium (success only) |
| Transcript checkpoint persistence semantics | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:98`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:114` | `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:97` | Strong |
| Batched vs immediate persistence behavior | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:39`, `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:51` | `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:7`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:32` | Strong |
| Runtime event and delta coalescing | `apps/CodexChatApp/Sources/CodexChatApp/RuntimeEventDispatchBridge.swift:118`, `apps/CodexChatApp/Sources/CodexChatApp/ConversationUpdateScheduler.swift:26` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeEventDispatchBridgeTests.swift:6`, `apps/CodexChatApp/Tests/CodexChatAppTests/ConversationUpdateSchedulerTests.swift:7` | Strong |
| Metadata migration/schema correctness | `packages/CodexChatInfra/Sources/CodexChatInfra/MetadataDatabase.swift:32` | `packages/CodexChatInfra/Tests/CodexChatInfraTests/CodexChatInfraTests.swift:8` | Strong |
| Follow-up queue repository behavior | `packages/CodexChatInfra/Sources/CodexChatInfra/SQLiteFollowUpQueueRepository.swift:61` | `packages/CodexChatInfra/Tests/CodexChatInfraTests/CodexChatInfraTests.swift:307`, `packages/CodexChatInfra/Tests/CodexChatInfraTests/SQLiteFollowUpQueueRepositoryTests.swift:7` | Medium |
| RuntimePool worker failure/restart behavior (degrade/reassign/restart loops) | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:376`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:440` | `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:5` | Weak |
| Auto-recovery backoff schedule exactness (`[1,2,4,8]`) | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352` | No direct assertion found in inspected tests | Missing |
| Crash-boundary transcript durability under interrupted write (temp-file replace failure modes) | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555` | No direct fault-injection assertion found in inspected tests | Missing |

## 5) Doc Staleness Findings (with file paths)

1. `docs-public/planning/feature-inventory.md:45` still labels stale mapping recreation as `Assumption`, but this behavior is now explicit in runtime code and smoke tests.  
Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:157`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:153`.

2. `docs-public/planning/workstreams.md:14` prescribes `AppModel+RuntimeState.swift`, `AppModel+UXState.swift`, `AppModel+ExtensibilityState.swift` as decoupling prep files, but these files are not present in current source layout.  
Evidence: `docs-public/planning/workstreams.md:14` and missing paths under `apps/CodexChatApp/Sources/CodexChatApp/`.

3. Runtime/data reliability invariants are spread across docs (`AGENTS.md`, `docs-public/ARCHITECTURE_CONTRACT.md`, planning docs) without a single contributor-facing runtime foundation contract document.  
Evidence: `AGENTS.md:45`, `docs-public/ARCHITECTURE_CONTRACT.md:27`, `docs-public/planning/feature-inventory.md:38`.

Assumption: Item 2 may be an intentionally unexecuted planning step rather than an accidental stale statement; it is still a practical drift signal for new contributors.

## 6) Refactor Opportunities (ranked by impact and merge risk)

| Rank | Opportunity | Impact | Merge Risk | Evidence |
|---|---|---|---|---|
| 1 | Introduce a single `RuntimeRecoveryPolicy` used by AppModel and RuntimePool (attempt caps + backoff schedule source of truth). | High (prevents policy drift, clarifies bounded guarantees). | Medium | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:352`, `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:446`. |
| 2 | Consolidate failure classification (`failed/error/cancel`) into one helper shared by runtime event handling and persistence. | Medium (reduces behavioral divergence on failure paths). | Low | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift:591`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimePersistence.swift:20`. |
| 3 | Centralize runtime-thread mapping mutations into one internal service (cache + repository + pin/unpin). | High (reduces subtle mapping drift bugs). | Medium | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:486`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:575`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:601`. |
| 4 | Split protocol-compatibility fallback heuristics into shared policy between CodexKit param builders and AppModel turn fallback. | Medium (clearer compatibility strategy and testability). | Medium | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:683`, `packages/CodexKit/Sources/CodexKit/CodexRuntime+Params.swift:177`. |
| 5 | Add dedicated RuntimePool resilience tests (worker terminate, pin reassignment, repeated restart failures). | High (locks reliability behavior under refactors). | Low | `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift:376`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolTests.swift:5`. |

