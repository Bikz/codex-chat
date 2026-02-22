# Parallel Workstreams (Exactly 3)

## Goal
Define 3 streams that can run in parallel with minimal code overlap and safe merge behavior in a multi-agent, dirty-worktree workflow.

## Decoupling-First Plan (Run Before Parallel Implementation)
The current architecture is modular but still has a few high-contention files. Before broad parallel edits, apply these coordination rules:

1. Freeze high-contention files behind ownership:
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel.swift`: contract/state hub only.
- `apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift`: owned by Workstream 2 only.
- `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift`: no new tests here; add stream-specific test files.

2. Add stream-specific extension files for new state or behaviors:
- `AppModel+RuntimeState.swift` (Workstream 1)
- `AppModel+UXState.swift` (Workstream 2)
- `AppModel+ExtensibilityState.swift` (Workstream 3)

3. Contract-first change policy:
- `packages/CodexChatCore` is owned by Workstream 1.
- Workstreams 2 and 3 consume contracts via adapters/extensions; avoid direct schema/model edits unless routed through Workstream 1.

---

## Workstream 1: Runtime Reliability + Data Foundation
- Mission: Keep turns, approvals, persistence, and recovery correct under load and failures.
- Scope:
1. Runtime session lifecycle, routing, sharding, restart/backoff.
2. Turn dispatch, thread mapping, checkpoint/archive persistence, search indexing.
3. Approval queues, follow-up queue reliability, startup recovery/storage migrations.
4. Metadata schema/repository evolution and compatibility.
- Out of scope:
1. Visual layout/styling and primary UI ergonomics.
2. Mods/skills/extensions/computer-action feature expansion.
- Owned files/dirs (exclusive):
1. `packages/CodexKit/**`
2. `packages/CodexChatInfra/**`
3. `packages/CodexChatCore/**`
4. `apps/CodexChatApp/Sources/CodexChatApp/RuntimePool.swift`
5. `apps/CodexChatApp/Sources/CodexChatApp/RuntimePoolModels.swift`
6. `apps/CodexChatApp/Sources/CodexChatApp/CodexRuntimeWorker.swift`
7. `apps/CodexChatApp/Sources/CodexChatApp/AdaptiveConcurrencyController.swift`
8. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift`
9. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift`
10. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimePersistence.swift`
11. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeThreadPrewarm.swift`
12. `apps/CodexChatApp/Sources/CodexChatApp/RuntimeThreadResolutionCoordinator.swift`
13. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Approvals.swift`
14. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift`
15. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Threads.swift`
16. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift`
17. `apps/CodexChatApp/Sources/CodexChatApp/ChatArchiveStore.swift`
18. `apps/CodexChatApp/Sources/CodexChatApp/PersistenceBatcher.swift`
19. `apps/CodexChatApp/Sources/CodexChatApp/TurnPersistenceWorker.swift`
20. `apps/CodexChatApp/Sources/CodexChatApp/TurnPersistenceScheduler.swift`
- API/contracts with other streams:
1. Runtime/conversation read models exposed through `AppModel` published state (`runtimeStatus`, `conversationState`, `pending approvals`, `follow-up queues`).
2. Schema/model contract ownership in `CodexChatCore` and `CodexChatInfra`.
3. Failure/repair signals exposed as action cards + log levels (consumed by Workstream 2 UI).
- Risks:
1. Schema migration mistakes can orphan user data.
2. Thread/approval mapping regressions can misroute actions.
3. High-throughput delta handling can starve UI if batching regresses.
- Milestones:
1. M1: Runtime/dispatch correctness baseline (mapping, retry-on-stale, approval continuity).
2. M2: Persistence hardening (archive checkpoints, search indexing, migration safety).
3. M3: Throughput + resilience tuning (runtime pool health/backoff/adaptive limits).
4. M4: Contract freeze and compatibility docs for downstream streams.

## Workstream 2: Product UX + Workspace Surfaces
- Mission: Deliver a consistent, accessible, two-pane user experience across core chat workflows.
- Scope:
1. Sidebar, canvas, onboarding, settings, project settings, diagnostics UI.
2. Conversation rendering modes, transcript presentation, inline states.
3. Shell workspace UX, voice capture UX, review flows, accessibility polish.
- Out of scope:
1. Runtime protocol logic and storage schema changes.
2. Skills/mods/extensions/native action backend behavior.
- Owned files/dirs (exclusive):
1. `apps/CodexChatHost/**`
2. `packages/CodexChatUI/**`
3. `apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift`
4. `apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift`
5. `apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift`
6. `apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift`
7. `apps/CodexChatApp/Sources/CodexChatApp/TranscriptPresentation.swift`
8. `apps/CodexChatApp/Sources/CodexChatApp/ChatSetupView.swift`
9. `apps/CodexChatApp/Sources/CodexChatApp/SettingsView.swift`
10. `apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift`
11. `apps/CodexChatApp/Sources/CodexChatApp/NewProjectSheet.swift`
12. `apps/CodexChatApp/Sources/CodexChatApp/ReviewChangesSheet.swift`
13. `apps/CodexChatApp/Sources/CodexChatApp/ModChangesReviewSheet.swift`
14. `apps/CodexChatApp/Sources/CodexChatApp/ApprovalRequestSheet.swift`
15. `apps/CodexChatApp/Sources/CodexChatApp/DangerConfirmationSheet.swift`
16. `apps/CodexChatApp/Sources/CodexChatApp/DiagnosticsView.swift`
17. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Search.swift`
18. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+VoiceCapture.swift`
19. `apps/CodexChatApp/Sources/CodexChatApp/VoiceCaptureService.swift`
20. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+ShellState.swift`
21. `apps/CodexChatApp/Sources/CodexChatApp/ShellWorkspaceDrawer.swift`
22. `apps/CodexChatApp/Sources/CodexChatApp/ShellTerminalPaneView.swift`
23. `apps/CodexChatApp/Sources/CodexChatApp/ShellSplitTree.swift`
24. `apps/CodexChatApp/Sources/CodexChatApp/ShellSplitContainerView.swift`
25. `apps/CodexChatApp/Sources/CodexChatApp/ShellPaneChromeView.swift`
- API/contracts with other streams:
1. Consumes runtime state contracts from Workstream 1; no direct runtime worker calls from views.
2. Consumes extensibility state contracts from Workstream 3 (`skills/mods availability`, `mods bar action descriptors`).
3. Owns final interaction/state rendering semantics for empty/loading/error/success surfaces.
- Risks:
1. UI can become inconsistent if state contracts are ambiguous.
2. Accessibility regressions on rapidly evolving interactive surfaces.
3. Toolbar/content contention if non-owners edit `ContentView.swift`.
- Milestones:
1. M1: Normalize state surfaces across sidebar/canvas/settings.
2. M2: Accessibility and keyboard-navigation pass.
3. M3: Shell + voice + diagnostics UX hardening.
4. M4: Two-pane IA compliance audit (no persistent third pane regressions).

## Workstream 3: Extensibility + Automation Platform
- Mission: Expand safe automation and customization via skills, mods, extensions, and native actions.
- Scope:
1. Skills discovery/install/update/enablement and composer integration.
2. Mods install/validation/discovery/theme, mods bar actions.
3. Extension hooks/event bus/automation scheduling + permissions.
4. Native computer actions + harness bridge + adaptive intent routing.
5. Plan runner orchestration and persisted plan task state.
- Out of scope:
1. Core runtime sharding/mapping/persistence internals.
2. Generic UI shell/layout concerns outside extensibility surfaces.
- Owned files/dirs (exclusive):
1. `packages/CodexSkills/**`
2. `packages/CodexMods/**`
3. `packages/CodexExtensions/**`
4. `packages/CodexComputerActions/**`
5. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Skills.swift`
6. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Mods.swift`
7. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+ModsSurface.swift`
8. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift`
9. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift`
10. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActionHarness.swift`
11. `apps/CodexChatApp/Sources/CodexChatApp/ComputerActionHarnessServer.swift`
12. `apps/CodexChatApp/Sources/CodexChatApp/ComputerActionHarnessModels.swift`
13. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdaptiveIntent.swift`
14. `apps/CodexChatApp/Sources/CodexChatApp/AppModel+PlanRunner.swift`
15. `apps/CodexChatApp/Sources/CodexChatApp/PlanRunner/**`
16. `apps/CodexChatApp/Sources/CodexChatApp/SkillsCanvasView.swift`
17. `apps/CodexChatApp/Sources/CodexChatApp/SkillsModsCanvasView.swift`
18. `apps/CodexChatApp/Sources/CodexChatApp/SkillInstallViews.swift`
19. `apps/CodexChatApp/Sources/CodexChatApp/ModViews.swift`
20. `apps/CodexChatApp/Sources/CodexChatApp/ExtensionModsBarView.swift`
21. `apps/CodexChatApp/Sources/CodexChatApp/ComputerActionPreviewSheet.swift`
22. `mods/first-party/**`
23. `skills/first-party/**`
- API/contracts with other streams:
1. Emits extension/mods-bar action models consumed by Workstream 2 UI.
2. Uses runtime dispatch/approval contracts from Workstream 1 for safe execution.
3. Persists through repositories/contracts owned by Workstream 1; schema changes routed via Workstream 1.
- Risks:
1. Permission escalation surface area grows quickly.
2. Catalog/install inputs are untrusted and require strict validation.
3. Action bridge failures can produce confusing mixed runtime/native states.
- Milestones:
1. M1: Skills/mods install/update reliability + schema hardening.
2. M2: Extension automation permission and failure-retry correctness.
3. M3: Native action + harness safety and recovery consistency.
4. M4: Plan runner completion-marker robustness and operator UX.

---

## Overlap Matrix
Legend: `0` = no planned file/dir overlap, `!` = unavoidable shared contract hotspot.

| Stream Pair | Overlap Level | Planned Intersections |
|---|---|---|
| 1 ↔ 2 | 0 | None (runtime/data vs UI-only split) |
| 1 ↔ 3 | ! | `apps/CodexChatApp/Sources/CodexChatApp/AppModel.swift`, `packages/CodexChatCore/**` |
| 2 ↔ 3 | ! | `apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift` (toolbar/surface wiring only) |

## Explicit Overlap List + Mitigation
1. `apps/CodexChatApp/Sources/CodexChatApp/AppModel.swift`
- Mitigation: no feature logic edits here; add per-stream extension files for new state and computed properties.

2. `packages/CodexChatCore/**`
- Mitigation: Workstream 1 owns contract changes; Workstream 3 opens contract-request PRs first, then rebases.

3. `apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift`
- Mitigation: Workstream 2 is sole editor; Workstream 3 exposes toggles/actions through existing `AppModel` surface.

4. `apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift`
- Mitigation: freeze for new test additions; create stream-specific test files to avoid merge contention.

---

## Recommended Team Assignment
1. Team A (Runtime/Data): senior Swift concurrency + persistence focus; owns stream 1.
2. Team B (UX): SwiftUI/accessibility specialists; owns stream 2.
3. Team C (Extensibility): sandboxing/automation/tooling specialists; owns stream 3.

## Recommended Merge Order
1. Merge contract/decoupling prep (ownership freeze + extension state files).
2. Merge Workstream 1 foundations first (contracts/repositories/runtime guarantees).
3. Merge Workstream 3 next (extensibility features against stable contracts).
4. Merge Workstream 2 last for UX convergence and final cross-stream integration polish.

Rationale:
- Stream 1 defines most shared contracts.
- Stream 3 depends on runtime/data safety semantics.
- Stream 2 can integrate finalized capabilities with the least rebasing risk.
