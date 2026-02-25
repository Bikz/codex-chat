# Team A Runtime Foundation: Built vs Next

Date: 2026-02-23  
Scope: Runtime reliability + data foundation planning for CodexChat’s macOS-native, two-pane, local-first constraints.

Assumption: Priorities below optimize for reliability risk reduction and merge safety before feature breadth.
Assumption: P0 means "blocks confidence in runtime/data invariants under failure," not "customer-visible feature gap."
Assumption: Severity tiers in section 2 now distinguish release-defect backlog (none open) from strategic roadmap investment work.

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
| Follow-up queue fairness under high fan-out | Candidate selection now has direct fairness/starvation regression coverage across high fan-out thread sets. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:400`, `packages/CodexChatCore/Sources/CodexChatCore/Repositories.swift:81`, `packages/CodexChatInfra/Tests/CodexChatInfraTests/SQLiteFollowUpQueueFairnessTests.swift:6` |
| Storage repair operator runbook | Codex Home normalization/quarantine behavior now has an explicit operator runbook with troubleshooting and escalation steps. | `docs-public/STORAGE_REPAIR_RUNBOOK.md:1`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:260`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:127` |
| Workstream coordination contract refresh | Planning workstreams now align with multi-agent shared-worktree collaboration (no stale prep-file references, no exclusive ownership wording). | `docs-public/planning/workstreams.md:14`, `docs-public/planning/workstreams.md:35`, `AGENTS.md:92` |
| Approval continuity | Pending approvals reset with explicit UX messaging on communication failure and restart. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:884`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeApprovalContinuityTests.swift:8`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppRuntimeSmokeTests.swift:306` |
| Transcript durability | Checkpoint phases and atomic write path with fault-injection tests for write-denial, replace-boundary failure, and crash-leftover temp artifacts. | `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift:555`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:207`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:208`, `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:362` |
| Completion persistence pressure handling | Batcher threshold, shutdown, and max-pending spill are directly tested. | `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift:10`, `apps/CodexChatApp/Tests/CodexChatAppTests/PersistenceBatcherTests.swift:101` |
| Runtime option compatibility fallback | Retry-without-turn-options heuristics are codified and directly tested. | `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:671`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeTurnOptionsFallbackTests.swift:7` |
| Turn-options compatibility policy seam | Compatibility fallback heuristics now live in a dedicated policy type with direct unit coverage. | `apps/CodexChatApp/Sources/CodexChatApp/RuntimeTurnOptionsCompatibilityPolicy.swift:4`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift:693`, `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimeTurnOptionsCompatibilityPolicyTests.swift:4` |
| Runtime/data reliability contract | Dedicated runtime/data invariants contract is published and cross-linked from architecture and contributor docs. | `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md:1`, `docs-public/ARCHITECTURE_CONTRACT.md:4`, `AGENTS.md:46` |
| Local reliability gate | Team A reliability harness and pre-push flow are scriptable and enforced through make targets. | `scripts/runtime-reliability-local.sh:1`, `Makefile:40`, `Makefile:43`, `README.md:85` |
| Reliability scorecard artifacts | Local scorecard script writes machine-readable and human-readable reports for deterministic gates. | `scripts/runtime-reliability-scorecard.sh:1`, `Makefile:43`, `README.md:93` |
| Replay + ledger prototype | CLI supports replaying persisted thread artifacts and exporting deterministic event-ledger JSON. | `apps/CodexChatApp/Sources/CodexChatCLI/main.swift:22`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatRuntimeReliabilityArtifacts.swift:178`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatRuntimeReliabilityArtifacts.swift:227`, `docs-public/RUNTIME_LEDGER_REPLAY.md:1` |
| Runtime policy-as-code validation | Tracked runtime policy defaults are validated via CLI and included in local reliability harness flow. | `config/runtime-policy/default-policy.json:1`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatRuntimeReliabilityArtifacts.swift:256`, `scripts/runtime-reliability-local.sh:41`, `docs-public/RUNTIME_POLICY_AS_CODE.md:1` |
| Lean hosted CI | Hosted CI path is minimized to hosted quick smoke only (`make quick`) to reduce minute consumption. | `.github/workflows/ci.yml:1`, `.github/workflows/ci.yml:55` |
| Reliability diagnostics bundle | One-command local diagnostics bundle captures doctor/smoke/policy checks plus scorecard artifacts into a portable archive. | `scripts/runtime-reliability-bundle.sh:1`, `Makefile:46`, `README.md:103`, `docs-public/RUNTIME_RELIABILITY_BUNDLE.md:1` |
| Ledger migration/backfill planning | A migration-safe backfill plan now specifies dual-write rollout, idempotent markers, fallback read semantics, and crash-safe requirements. | `docs-public/planning/runtime-ledger-migration-backfill-plan.md:1` |
| Ledger backfill execution path | CLI backfill scans archived thread artifacts, exports missing ledgers, and writes idempotent per-thread marker files with force rerun support. | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatCLICommandParser.swift:47`, `apps/CodexChatApp/Sources/CodexChatCLI/main.swift:112`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatRuntimeReliabilityArtifacts.swift:174`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatRuntimeReliabilityArtifactsTests.swift:165` |
| Backfill full-history + stale-marker safety | Backfill now defaults to full-history export and only skips threads when markers decode and point to existing ledgers; stale markers are self-healed via re-export. | `apps/CodexChatApp/Sources/CodexChatApp/CodexChatCLICommandParser.swift:301`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatRuntimeReliabilityArtifacts.swift:359`, `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatRuntimeReliabilityArtifactsTests.swift:232` |

## 2) What Must Be Built Next (Prioritized Backlog)

Release-defect backlog status (2026-02-23 sweep):
1. P0: none open.
2. P1: none open.
3. P2: none open.
Evidence: local gates passed (`make quick`, `make oss-smoke`, `make reliability-local`, `make reliability-scorecard`) on this branch after backfill hardening updates.

Strategic roadmap backlog (non-defect):

### P0

1. No open P0 reliability gaps in the current runtime/data foundation slice.
Evidence: former P0 gaps (archive replacement-boundary durability and follow-up fairness under fan-out) now have direct regression coverage in `apps/CodexChatApp/Tests/CodexChatAppTests/ChatArchiveStoreCheckpointTests.swift:208` and `packages/CodexChatInfra/Tests/CodexChatInfraTests/SQLiteFollowUpQueueFairnessTests.swift:6`.

### P1

1. Expand reliability harness with additional deterministic fault-injection fixtures beyond current repro set (for example mixed interruption + partial persistence edge cases).
Evidence seed: current repro lanes exist in `apps/CodexChatApp/Fixtures/repro/runtime-termination-recovery.json:1` and `apps/CodexChatApp/Fixtures/repro/stale-thread-remap.json:1`.

2. Implement dual-write ledger persistence and migration markers from the published backfill plan.
Evidence seed: plan exists (`docs-public/planning/runtime-ledger-migration-backfill-plan.md:1`) but runtime write-path implementation is not landed yet.

### P2

1. Add optional longer-running RuntimePool recovery soak lane in CI once budget is allocated.
Evidence seed: deterministic resilience fixtures now exist (`apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171`).

2. Align app-level turn-options compatibility policy with CodexKit request/schema contracts.
Evidence gap: fallback heuristic has been extracted in app code, but cross-package contract linkage remains implicit (`apps/CodexChatApp/Sources/CodexChatApp/RuntimeTurnOptionsCompatibilityPolicy.swift:4`, `packages/CodexKit/Sources/CodexKit/CodexRuntime+Params.swift:177`).

## 3) 30/60/90 Day Roadmap Slices

### Day 0-30

1. Propose optional CI soak lane design for repeated runtime-pool recovery cycles.
2. Draft app-level high-fanout auto-drain fairness integration test plan (runtime + repository path).
3. Prepare CodexKit alignment note for the extracted compatibility policy seam.

Dependencies:
- Existing resilience and fairness baselines: `apps/CodexChatApp/Tests/CodexChatAppTests/RuntimePoolResilienceTests.swift:171`, `packages/CodexChatInfra/Tests/CodexChatInfraTests/SQLiteFollowUpQueueFairnessTests.swift:6`.

### Day 31-60

1. Add shared acceptance criteria snippets to planning docs referencing reliability contract.
2. Start CodexKit alignment implementation for turn-options compatibility policy.
3. Land first optional CI soak lane implementation if budget is approved.

Dependencies:
- P0 reliability baseline remains green.
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

2. Add an explicit contract note for follow-up queue fairness expectations with the new high-fan-out test evidence.

3. Add explicit CI guidance for optional long-running resilience soak lanes.

### Migration considerations

1. Data migration:
- No SQLite schema migration is required for the changes landed in this slice.

2. Behavior migration:
- Shared recovery policy has already been introduced behind existing regression tests; preserve current delay/attempt semantics while extending coverage.

3. Documentation migration:
- Keep `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md` as the canonical invariant source and ensure planning docs link back to it for future updates.

Assumption: No UI IA migration is required because all changes stay inside existing two-pane surfaces and explicit messaging paths.
