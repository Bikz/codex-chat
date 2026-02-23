# Team C Extensibility + Automation Platform Built vs Next

Date: 2026-02-23

## 1) Already built (evidence table)
| Capability area | Already built now | Evidence |
|---|---|---|
| Skills lifecycle | Multi-root discovery, git+npx install, git update, reinstall with atomic rollback | `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:296`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:371`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:439`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:775` |
| Mod package hardening | Mandatory `codex.mod.json`, safe entrypoint checks, permission declaration validation, optional checksum validation | `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModPackageManifest.swift:173`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModPackageManifest.swift:190`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModPackageManifest.swift:295`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModPackageManifest.swift:223` |
| Mod source installer | Local and GitHub (`tree`) install support, `blob` rejection guidance, update rollback | `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModInstallService.swift:133`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModInstallService.swift:285`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModInstallService.swift:205` |
| Executable mod guardrail | Advanced executable lock for non-vetted mods with migration behavior for existing users | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdvancedExecutableMods.swift:16`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdvancedExecutableMods.swift:76`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ModsSurface.swift:296` |
| Extension worker runtime | Protocol v1 envelope + bounded process execution and typed output | `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionModels.swift:165`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift:46`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift:105` |
| Extension app orchestration | Hook/automation execution, permission prompts, mods bar state persistence, project-scoped artifact writes | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:489`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:644`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:741`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:768` |
| Mods bar action platform | Composer insert/send, event emission, prompt-input events, native action launch from mods bar | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:331`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionModels.swift:236` |
| Automation execution | In-process scheduler with retry backoff and optional launchd background scheduling (`runWhenAppClosed`) | `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionAutomationScheduler.swift:53`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:939`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/LaunchdManager.swift:82` |
| Native actions | Registry of desktop/calendar/reminders/messages/files/applescript actions with preview-confirm-execute and undo for desktop cleanup | `/Users/bikram/Developer/CodexChat/packages/CodexComputerActions/Sources/CodexComputerActions/ComputerActionRegistry.swift:39`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift:86`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift:211` |
| Harness bridge | Local unix socket server, tokenized invocation, `queued_for_approval` bridging to existing approval UX | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ComputerActionHarnessServer.swift:31`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActionHarness.swift:84`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActionHarness.swift:150` |
| Adaptive intent | Intent parser for desktop/calendar/reminders/messages/plan/role with auto-routing only for native actions | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdaptiveIntent.swift:6`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdaptiveIntent.swift:38` |
| Plan runner | Markdown task parsing, dependency scheduler, marker parsing, task/run persistence updates, cancel path | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+PlanRunner.swift:126`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+PlanRunner.swift:454`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/PlanRunner/PlanParser.swift:37`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/PlanRunner/PlanScheduler.swift:33` |

## 2) Execution status update (2026-02-23)

### Completed now (executed on this branch)
| Priority | Shipped item | Evidence | Commit(s) |
|---|---|---|---|
| P0 | Hardened harness bridge test coverage for malformed JSON, oversized payloads, protocol/token checks | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ComputerActionHarnessServerTests.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/AppModelHarnessAuthorizationTests.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ComputerActionHarnessServer.swift:202` | `9c53fa1`, `8809372` |
| P0 | Closed doc-vs-code drift for personal actions + security model | `/Users/bikram/Developer/CodexChat/docs-public/PERSONAL_ACTIONS.md`, `/Users/bikram/Developer/CodexChat/docs-public/SECURITY_MODEL.md`, `/Users/bikram/Developer/CodexChat/packages/CodexComputerActions/Sources/CodexComputerActions/ComputerActionRegistry.swift:39` | `0c47823` |
| P0 | Defined and enforced plan-runner capability contract before execution | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/PlanRunner/PlanParser.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/PlanRunner/PlanRunnerCapabilityPolicy.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+PlanRunner.swift` | `5a69be5` |
| P1 | Added launchd manager reliability tests and injectable command runner | `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Tests/CodexExtensionsTests/LaunchdManagerTests.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/LaunchdManager.swift` | `da7d822` |
| P1 | Added skill provenance hardening (explicit untrusted-source confirmation + git pinning) | `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Skills.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Tests/CodexSkillsTests/CodexSkillsTests.swift` | `9d9f517` |
| P1 | Added advanced executable-mod lock regression tests (migration + install-time disabled behavior) | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/AppModelAdvancedExecutableModsTests.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdvancedExecutableMods.swift:16`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ModsSurface.swift:296` | `2353310` |
| P1 | Added extension artifact path-safety regression coverage + shared path helper | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectPathSafety.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ProjectPathSafetyTests.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ModsBarActionTests.swift` | `307aa26`, `a11f298` |
| P0 | Added extension worker malformed-output and output-limit negative tests | `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Tests/CodexExtensionsTests/CodexExtensionsTests.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift:105` | `c8ff0ca` |
| P1 | Added scheduler retry/backoff regression coverage with deterministic sleep injection | `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionAutomationScheduler.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Tests/CodexExtensionsTests/ExtensionAutomationSchedulerTests.swift` | `e233543` |
| P0 | Added fuzz-style malformed framing tests across harness and extension worker boundaries | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ComputerActionHarnessServerTests.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Tests/CodexExtensionsTests/CodexExtensionsTests.swift` | `bd501b8` |
| P2 (kickoff) | Extracted shared extensibility capability policy primitive and wired plan-runner policy through it | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ExtensibilityCapabilityPolicy.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/PlanRunner/PlanRunnerCapabilityPolicy.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ExtensibilityCapabilityPolicyTests.swift` | `7a02738` |
| P2 | Adopted shared capability policy in extension and native-action permission gates (with regression coverage) | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ModsBarActionTests.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/AppModelComputerActionsTests.swift` | `759c6de` |
| P2 | Extended shared capability policy to skill-install trust checks for untrusted projects | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Skills.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/AppModelSkillsTrustPolicyTests.swift` | `b0e38b2` |
| P2 | Extended shared capability policy to mod install/update trust checks for untrusted projects | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ModsSurface.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/AppModelModsTrustPolicyTests.swift` | `c345a43` |
| P2 | Hardened skill/mod process runners with timeout and output-cap safeguards plus package-level regression tests | `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModInstallService.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Tests/CodexSkillsTests/CodexSkillsTests.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Tests/CodexModsTests/ModInstallServiceTests.swift` | `49418d9` |
| P2 | Marked background-automation capability as privileged for untrusted projects via shared policy | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ExtensibilityCapabilityPolicy.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ExtensibilityCapabilityPolicyTests.swift` | `049f2d1` |
| P2 | Added automation health read-model + Mods UI surface for per-mod next/last/failure status | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ModsSurface.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ModViews.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/ExtensionAutomationHealthTests.swift` | `03de497` |
| P2 | Extracted shared bounded process-runner package and adopted it in skills/mods installers | `/Users/bikram/Developer/CodexChat/packages/CodexProcess/Sources/CodexProcess/BoundedProcessRunner.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModInstallService.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexProcess/Tests/CodexProcessTests/CodexProcessTests.swift` | `77aa36c` |
| P2 | Migrated extension worker execution onto shared `CodexProcess` runner and preserved strict output-limit enforcement in extension contract | `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Package.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexProcess/Sources/CodexProcess/BoundedProcessRunner.swift`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Tests/CodexExtensionsTests/CodexExtensionsTests.swift:196` | `f0ee05c` |

### Remaining prioritized backlog

### P0 (safety/reliability critical)
1. No open P0 safety blockers in Team C scope for this cycle.

### P2 (platform evolution and maintainability)
1. Unify process execution adapters.
- Phase 3 shipped: skills/mods/extensions now all execute through shared `CodexProcess` bounded runner primitives.
- Next step is unifying process telemetry and failure-taxonomy reporting across app surfaces.
- References: `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift:46`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:882`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModInstallService.swift:562`.

2. Improve automation observability UX.
- Phase 1 shipped: per-mod automation health summaries now surface last/next/failure status in the Mods UI.
- Next step is wiring launchd and scheduler telemetry into a single richer status timeline and explicit failure-recovery affordances.
- References: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:810`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionAutomationScheduler.swift:48`.

## 3) 30/60/90 day roadmap (re-baselined)

### 0-30 days
1. Define a unified telemetry schema for shared process-runner outcomes (skills/mods/extensions).
2. Extend shipped automation health summary into unified launchd+scheduler status contract.

Exit criteria:
- Shared policy/process design is reviewed and approved by runtime + UX workstreams.

### 31-60 days
1. Add first integration seam between consolidated process-executor telemetry and policy outcomes.
2. Implement shared automation observability model between in-app scheduler and launchd.
3. Draft migration plan for historical automation status records.

Exit criteria:
- One policy decision model can represent current extension/native-action/skill checks.
- Plan-runner uses the same policy vocabulary.
- Migration impact is documented and test strategy is defined.

### 61-90 days
1. Complete policy-aware process telemetry plumbing across skills/mods/extensions.
2. Land unified automation observability state model and UI bindings.
3. Complete de-duplication of path/process safety helpers across Team C packages.

Exit criteria:
- Fewer duplicated execution paths across skills/mods/extensions.
- Automation health is visible through one coherent model.
- Cross-surface safety checks share reusable primitives.

## 4) Dependencies on Runtime contracts and UX integration points

### Runtime dependencies (Workstream 1)
- Team C relies on runtime dispatch/approval contracts for safe execution and user confirmation continuity.
- Team C persistence changes route through repositories/contracts owned by Workstream 1.
- References: `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:156`, `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:157`.

### UX integration dependencies (Workstream 2)
- Team C emits mods bar models/actions consumed by Team B surfaces.
- Team C must preserve two-pane UX contract; new extensibility controls belong in sheets/cards/drawers, not persistent third panes.
- References: `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:155`, `/Users/bikram/Developer/CodexChat/AGENTS.md:10`, `/Users/bikram/Developer/CodexChat/AGENTS.md:11`.

Assumption: Workstream ownership boundaries in `workstreams.md` remain stable throughout this roadmap.

## 5) De-risking plan for permission and external-input surfaces
1. Apply default-deny policy for new privileged capability keys.
- Require explicit grant + stored decision before execution.
- Existing precedent: extension permission store, native action permission prompts, and untrusted-project skill install gates.
- Evidence: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Skills.swift`.

2. Strengthen provenance and integrity checks at install/update time.
- Skills: add source pinning and stricter trust policy.
- Mods: enforce or strongly recommend checksum on remote sources.
- Evidence: `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:518`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModPackageManifest.swift:223`.

3. Expand negative-path testing for external input boundaries.
- Harness malformed/oversized input.
- Worker malformed output and boundary sizes.
- Artifact traversal attempts.
- Evidence: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ComputerActionHarnessServer.swift:202`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift:122`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:779`.

4. Keep local-first posture explicit in every extensibility path.
- Prefer local socket/processes, local state stores, and project-root-constrained writes.
- Evidence: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ComputerActionHarnessServer.swift:73`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionStateStore.swift:38`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:768`.
