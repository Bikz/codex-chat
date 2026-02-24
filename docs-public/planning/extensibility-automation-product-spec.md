# Extensibility + Automation Product Spec

## Owner
Team C: Extensibility + Automation Platform

## Status
Draft v1 (execution-oriented)

## Last Updated
2026-02-23

## Scope
This spec defines product behavior and roadmap for:
- Skills
- Mods
- Mods Bar (rail + panel)
- Extension hooks and automations
- Native computer actions and harness surfaces that are invoked from extensibility

This spec preserves the two-pane contract, keeps guardrails explicit, treats external input as untrusted, and maintains local-first behavior.

## Product Vision
CodexChat extensibility should feel like install-once, use-anywhere power with clear scope boundaries and explicit safety controls.

Users should be able to:
1. Discover what is installed and enabled.
2. Understand where a mod applies (global, project, thread).
3. Use non-thread-dependent mods in draft mode.
4. Switch active mod context quickly without disabling other mods.
5. Trust that risky actions are always gated and explainable.

## Product Principles
1. Conversation-first UX: no persistent third pane.
2. Local-first ownership of state and execution.
3. Explicit safety for privilege boundaries.
4. Predictable scope semantics.
5. Progressive complexity: simple defaults, advanced controls available.
6. Reliability by default: bounded execution, durable writes, diagnosable failures.

## Problem Statement
Current behavior creates avoidable confusion:
1. Mod settings are modeled as a single selected mod per scope, while the rail visually suggests multiple available mod surfaces.
2. Enabling one mod in a scope disables others.
3. Draft mode blocks mods bar usage when no thread is selected, including cases where output can be global.
4. Scope semantics are split across install scope (global/project) and output scope (thread/global), with no first-class project output scope.
5. Mod identity in the rail relies mostly on heuristics and can be ambiguous.

## Target Experience
### Mental Model
Each mod has three independent states:
1. Installed: files exist and validate.
2. Enabled: runtime surfaces are allowed to participate.
3. Focused: currently selected in the mods bar rail/panel.

### Scope Model
There are three content scopes:
1. Global: available across projects.
2. Project: available within current project.
3. Thread: available only in selected thread.

Install scope remains:
1. Global install
2. Project install

### Draft Mode
When no thread is selected:
1. Global/project-capable mods remain usable.
2. Thread-required mods show scoped empty state with clear explanation.
3. No blanket "No thread selected" block for all mods.

### Identity in Rail
Each enabled mod has:
1. Icon (mod-declared symbol if provided, else deterministic fallback).
2. Tooltip label (human-readable mod name + scope).
3. Stable order (project first, global second, then recency within each group).

## User Segments and Journeys
### Segment A: Daily Contributor
Journey:
1. Install Prompt Book once.
2. Open new draft and use prompt actions without selecting a thread.
3. Switch to thread-scoped summary when needed.

Success criteria:
- No confusion about why a mod is visible or unavailable.

### Segment B: Project Lead
Journey:
1. Install project mod for notes/checklists.
2. Keep multiple mods enabled concurrently.
3. Use rail as quick context switch.

Success criteria:
- No hidden disable side-effects.

### Segment C: Power User / Builder
Journey:
1. Build mod with hooks/automations.
2. Declare scope and thread requirements explicitly.
3. Validate permission prompts and diagnostics.

Success criteria:
- Clear contract, testable behavior, reliable failure diagnostics.

## Goals and OKRs
### Objective 1: Reduce extensibility confusion
Key Results:
1. Reduce "wrong mod active"/"mod disappeared" support incidents by 70%.
2. Increase first-time successful mod usage to >= 85% of new mod installs.
3. Reduce time-to-first-usable-mod to < 3 minutes median.

### Objective 2: Increase repeat usage
Key Results:
1. Increase weekly active mods bar users by 50%.
2. Increase users with >= 2 enabled mods by 40%.
3. Increase quick-switch interactions per active user by 30%.

### Objective 3: Strengthen safety confidence
Key Results:
1. 100% privileged operations pass explicit permission/confirmation path.
2. 0 high-severity regressions in path-containment and permission bypass tests.
3. Add explicit scope/thread dependency declarations to >= 90% first-party mods.

### Objective 4: Improve reliability and operability
Key Results:
1. Hook + automation process failure rate < 2% per run.
2. Mean time to diagnose extension failure < 5 minutes.
3. 100% of install/update flows have deterministic rollback or safe failure behavior.

## Guardrails and Trust Boundaries
1. External worker output is untrusted input.
2. Artifact writes must remain project-contained and atomic.
3. Permission prompts remain explicit with clear reason and scope.
4. Background automation remains separately permissioned.
5. Harness requests remain token-gated and local-only.

## Product Requirements
### R1: Multi-enabled runtime model
- Users can enable multiple mods per install scope.
- Focused mod selection must not implicitly disable others.
- Theme precedence remains explicit and deterministic.

### R2: Explicit mods bar scope support
- Support output scopes: `thread`, `project`, `global`.
- Backward compatibility for missing scope defaults.

### R3: Thread dependency declaration
- Mods bar schema supports thread requirement declaration.
- If no thread and thread-required, show scoped empty state for that mod.

### R4: Draft mode support
- Non-thread-dependent mods function in draft mode.
- Actions that need thread still gate with explicit messaging.

### R5: Identity and discoverability
- Every rail entry has icon + tooltip.
- Deterministic fallback icon assignment for mods without declared icon.

### R6: Diagnostics and recovery
- Surface per-mod runtime health and last failure context.
- Keep existing extensibility diagnostics stream and retention controls.

## Metrics and Instrumentation
### Activation
1. `ext.mod.install.success_rate`
2. `ext.mod.enable.success_rate`
3. `ext.mod.time_to_first_output_ms`

### Engagement
1. `ext.mods_bar.weekly_active_users`
2. `ext.mods_bar.quick_switch_count`
3. `ext.mods_bar.enabled_mod_count_per_user`

### Reliability
1. `ext.hook.failure_rate`
2. `ext.automation.failure_rate`
3. `ext.mods_bar.render_empty_unexpected_rate`

### Safety
1. `ext.permission.prompt_accept_rate`
2. `ext.permission.denial_recovery_rate`
3. `ext.unsafe_write_block_count`

## Prioritized Roadmap

### P0 (0-30 days): Correctness + UX alignment
1. Remove blanket draft-mode thread gate in mods bar view.
2. Allow global/project-capable mod usage without selected thread.
3. Separate focused mod from enablement state.
4. Update mods page language and controls to Installed/Enabled/Focused model.
5. Add regression tests for draft behavior and multi-enabled semantics.

Acceptance:
- Draft mode can use Prompt Book-like mods.
- Enabling one mod no longer disables unrelated enabled mods.

### P1 (31-60 days): Scope completeness + identity
1. Add first-class `project` output scope in extension state models.
2. Add schema support for icon metadata and thread requirement declaration.
3. Ship deterministic fallback icon resolver.
4. Group quick-switch entries by project/global scope with tooltips.
5. Expand first-party mods to declare scope/thread requirements.

Acceptance:
- First-party mods explicitly declare behavior.
- Rail identity is stable and understandable.

### P2 (61-90 days): Operability + hardening
1. Add per-mod health and recovery guidance in UI.
2. Unify permission center across extensibility surfaces.
3. Expand negative/fuzz tests for harness and worker outputs.
4. Finalize migration path away from legacy single-selection state.
5. Update public docs and contributor guides.

Acceptance:
- Diagnostics provide actionable root cause and next step.
- Migration is backward compatible with no user data loss.

## Dependencies
1. Runtime event envelope stability.
2. Extension protocol backward compatibility.
3. Preferences/project metadata migration support.
4. UX alignment in Skills & Mods and conversation canvas rail.

## Risks and Mitigations
1. Risk: Scope migration regressions.
Mitigation: additive schema changes and fallback defaults.

2. Risk: Increased runtime load from multi-enabled mods.
Mitigation: debounce controls, timeouts, health-based throttling.

3. Risk: Permission fatigue.
Mitigation: clearer reason text, grouped prompts, stable policy center.

4. Risk: UX complexity growth.
Mitigation: strict IA boundaries and progressive disclosure.

## Definition of Done
1. Scope semantics are explicit in schema, UI, and docs.
2. Draft mode works for non-thread-dependent mods.
3. Multi-enabled behavior is implemented and test-covered.
4. Icon + tooltip identity works across rail and quick switch.
5. Safety and reliability guardrails are preserved or improved.
6. Contributor docs reflect implementation reality.
