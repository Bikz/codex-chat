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

## 2) Next to build (prioritized backlog)

### P0 (safety/reliability critical)
1. Harden harness bridge test coverage.
- Add dedicated tests for request framing, max-size rejection, malformed JSON, token mismatch, and decode coercion.
- Evidence: harness server and handler have explicit guardrails but minimal direct tests today.
- References: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ComputerActionHarnessServer.swift:202`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActionHarness.swift:119`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:710`.

2. Close doc-vs-code safety drift in public docs.
- Update `PERSONAL_ACTIONS.md` and `SECURITY_MODEL.md` to match shipped action surface and routing defaults.
- References: `/Users/bikram/Developer/CodexChat/docs-public/PERSONAL_ACTIONS.md:5`, `/Users/bikram/Developer/CodexChat/docs-public/SECURITY_MODEL.md:67`, `/Users/bikram/Developer/CodexChat/packages/CodexComputerActions/Sources/CodexComputerActions/ComputerActionRegistry.swift:39`.

3. Define explicit plan-runner permission contract.
- Add explicit policy for plan tasks that trigger native actions/mod hooks, instead of only relying on downstream runtime approvals.
- References: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+PlanRunner.swift:218`, `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:156`.

### P1 (high value hardening + platform clarity)
1. Add launchd/background automation integration tests.
- Validate plist generation, bootstrap/bootout error handling, and `runWhenAppClosed` state updates.
- References: `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/LaunchdManager.swift:82`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:939`.

2. Introduce stronger skill provenance controls.
- Add optional commit/tag pinning and install-time policy checks for untrusted hosts (beyond hostname heuristic).
- References: `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:518`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:882`.

3. Add tests for advanced executable mods lock migration and enforcement.
- Verify existing-user migration, new-user default lock, and install-time disabled behavior.
- References: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdvancedExecutableMods.swift:16`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ModsSurface.swift:296`.

### P2 (platform evolution and maintainability)
1. Unify permission policy primitives across skills/mods/extensions/native actions.
- Replace split policy logic with a shared capability-policy module.
- References: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:644`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift:600`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:518`.

2. Unify process execution adapters.
- Build one common executor abstraction with per-surface limits and structured failure telemetry.
- References: `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionWorkerRunner.swift:46`, `/Users/bikram/Developer/CodexChat/packages/CodexSkills/Sources/CodexSkills/SkillCatalog.swift:882`, `/Users/bikram/Developer/CodexChat/packages/CodexMods/Sources/CodexMods/ModInstallService.swift:562`.

3. Improve automation observability UX.
- Surface unified “next run / last run / last failure” across in-app and launchd paths.
- References: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:810`, `/Users/bikram/Developer/CodexChat/packages/CodexExtensions/Sources/CodexExtensions/ExtensionAutomationScheduler.swift:48`.

## 3) 30/60/90 day roadmap

### 0-30 days
1. Ship doc corrections for personal actions/security model + quickstart caveat updates.
2. Add harness negative/fuzz-like request parsing tests.
3. Define and publish plan-runner permission contract doc.

Exit criteria:
- Public docs align with shipped action IDs and routing behavior.
- Harness failure modes are regression-tested.
- Plan runner permission boundaries are explicit and reviewed.

### 31-60 days
1. Add launchd integration tests and improve automation failure assertions.
2. Add advanced executable mod lock tests (migration + enforcement).
3. Prototype skill source pinning policy and installer UX messaging for untrusted sources.

Exit criteria:
- Background automation safety flows are testable and deterministic.
- Executable lock behavior is fully regression-covered.
- Skill trust posture is stronger than hostname allowlist alone.

### 61-90 days
1. Land shared capability-policy primitives across Team C surfaces.
2. Consolidate process execution wrappers into one policy-aware executor.
3. Ship unified automation observability model in app state.

Exit criteria:
- Fewer duplicated policy/process paths across skills/mods/extensions/native actions.
- Cross-surface permission outcomes are consistent and auditable.
- Background automations have one coherent health surface.

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
- Existing precedent: extension permission store and native action permission prompts.
- Evidence: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+Extensions.swift:644`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift:600`.

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
