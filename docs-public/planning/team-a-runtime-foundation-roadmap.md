# Team A Runtime Foundation Roadmap

Date: 2026-02-23
Owner: Team A (Runtime Reliability + Data Foundation)

Assumption: Team A has no self-hosted Apple Silicon runners yet.
Assumption: GitHub-hosted macOS minutes must be conserved; only fast guardrails should run remotely.
Assumption: The product contract remains macOS-native, two-pane, local-first, with explicit safety over hidden automation.

## North Star

Build the most trusted autonomous coding workstation on macOS by making runtime behavior provably reliable, data durability auditable, and failure recovery explicit.

## Strategy Shift (Now)

1. Make local reliability harness execution mandatory before push.
2. Keep GitHub-hosted CI minimal: fast checks + targeted smoke only.
3. Run deep reliability suites locally for now, with deterministic scripts and repeatable outputs.

## Implementation Status (Current Branch)

1. Completed:
- Local reliability harness + pre-push gate (`make reliability-local`, `make prepush-local`).
- Optional pre-push hook installer (`make install-local-hooks`).
- Hosted CI minimization to required `fast-checks` + `full-checks` where `full-checks` runs targeted smoke.
- Reliability scorecard generator (`make reliability-scorecard`) with JSON + markdown artifacts.
- Reliability diagnostics bundle generator (`make reliability-bundle`) with portable archive output.
- Local replay and ledger export CLI (`CodexChatCLI replay`, `CodexChatCLI ledger export`).
- Marker-based idempotent ledger backfill CLI (`CodexChatCLI ledger backfill`) for project archives.
- Backfill hardening: full-history default and stale-marker self-healing re-export behavior.
- Runtime policy-as-code validation CLI (`CodexChatCLI policy validate`) with tracked default policy file.
- Draft runtime reliability SLO document and replay/ledger + policy docs.
- Ledger migration/backfill plan document for event-sourced transition design.
- Additional deterministic repro fixtures for runtime termination recovery and stale-thread remap.

2. In progress:
- Extended fault-injection scenario breadth beyond current deterministic repro fixtures.
- Dual-write implementation for authoritative event ledger persistence.

## OKRs (Next 90 Days)

1. Objective: Prove runtime recovery behavior is deterministic.
- KR1: Local reliability harness covers restart backoff, stale-thread remap, approval reset continuity, and persistence durability paths.
- KR2: Harness is integrated into `make prepush-local` and can be enforced by a local git pre-push hook.
- KR3: At least 90% of runtime/data regressions are caught by harness + fast CI before merge.

2. Objective: Reduce hosted CI spend without reducing safety.
- KR1: PR required checks run only `make quick` and targeted smoke.
- KR2: Remove heavy hosted PR jobs from default CI path.
- KR3: Keep required status checks stable so branch protection remains predictable.

3. Objective: Build toward replayable local-first reliability.
- KR1: Establish deterministic test lanes for durability and recovery invariants.
- KR2: Define replay artifact requirements and a migration-safe event ledger plan.
- KR3: Publish contract updates when invariants change.

## Phased Execution Plan

### Phase 0 (This week)

1. Ship local reliability harness script with deterministic runtime/data invariant suites.
2. Add `make reliability-local` and `make prepush-local`.
3. Add optional local pre-push hook installer.
4. Slim hosted `ci.yml` to fast checks and targeted smoke checks only.

Exit criteria:
- Engineers can run one command before push for Team A reliability confidence.
- Required PR checks still pass branch protection while consuming fewer hosted minutes.

### Phase 1 (Weeks 2-4)

1. Add reproducible fault-injection fixtures for runtime termination and stale mapping scenarios.
2. Add deterministic crash-boundary transcript durability verification summary output.
3. Publish a reliability scorecard template (pass/fail by invariant + elapsed time).

Exit criteria:
- Reliability harness output is actionable and uniform across machines.
- Core reliability invariants are visible as a single pass/fail report.

### Phase 2 (Weeks 5-8)

1. Add local replay prototype from persisted turn artifacts.
2. Define event schema for runtime + persistence ledgering.
3. Add migration/backfill plan for existing transcript and metadata stores.

Exit criteria:
- A failed run can be replayed locally with deterministic sequencing.
- Data model for event-sourced reliability is documented.

### Phase 3 (Weeks 9-12)

1. Add policy-as-code enforcement surfaces for approvals/sandbox defaults.
2. Add verifiable enforcement logs for dangerous actions.
3. Finalize enterprise-facing reliability SLO draft (recovery time, durability integrity, approval continuity).

Exit criteria:
- Dangerous actions are traceable with explicit policy context.
- Reliability metrics align with enterprise operability targets.

## Team A Backlog (Priority)

### P0

1. Local reliability harness and pre-push flow.
2. Hosted CI minimization to `quick + targeted smoke`.
3. Documentation for how every engineer runs reliability checks locally.

### P1

1. Reliability scorecard output and trend capture.
2. Deterministic replay artifact format draft.
3. Extended fault-injection scenarios.

### P2

1. Event-sourced runtime ledger prototype.
2. One-click local recovery diagnostics bundle.
3. Future self-hosted runner migration plan (when budget/ops are ready).

## Release Hardening Sweep (2026-02-23)

1. Review scope covered all Team A branch deltas (`origin/main...team-a/runtime-foundation-next`) and validated runtime/data release gates.
2. Fixed high-risk backfill truncation defect by making `ledger backfill` default to full-history export.
3. Hardened stale marker handling so backfill only skips when markers decode and referenced ledger artifacts exist; otherwise re-export occurs.
4. Added regression tests for parser defaults, full-history backfill behavior, and stale-marker re-export recovery.
5. Current defect status for shipped Team A scope: no open P0/P1/P2 release defects.
Assumption: Remaining P1/P2 entries in this roadmap represent strategic investment work, not current defects.

## Risks and Mitigations

1. Risk: Local harness drift across developer machines.
- Mitigation: Keep harness deterministic, script-driven, and versioned in repo.

2. Risk: Reduced hosted CI coverage misses regressions.
- Mitigation: Preserve required quick + smoke checks and require local pre-push reliability harness.

3. Risk: Reliability work competes with feature velocity.
- Mitigation: Keep Team A scope contract-first and automate repeatable checks to reduce review overhead.

## Success Definition

1. Engineers can trust that a passing local pre-push run means low probability of runtime/data regression.
2. Hosted CI remains fast and affordable while preserving core guardrails.
3. Team A has a clear, staged path from current reliability primitives to provable, replayable runtime trust.
