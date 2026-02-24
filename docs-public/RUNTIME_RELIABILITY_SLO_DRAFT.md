# Runtime Reliability SLO Draft

Status: Draft for Team A iteration.
Date: 2026-02-23

## SLI Candidates

1. Runtime recovery success rate after unexpected termination.
2. Recovery latency (P50/P95) to usable runtime state.
3. Stale thread mapping self-heal success rate.
4. Approval continuity correctness (no dangling stale approvals).
5. Transcript durability integrity (no lost completed turns in crash-boundary checks).

## Initial SLO Targets (Draft)

1. Recovery success rate: `>= 99.0%`
2. Recovery P95 latency: `<= 15s`
3. Stale mapping self-heal: `>= 99.5%`
4. Approval continuity correctness: `100%`
5. Durability integrity in deterministic suite: `100%`

## Measurement Source

1. Local reliability harness (`make reliability-local`)
2. Reliability scorecard artifacts (`make reliability-scorecard`)
3. Thread replay and ledger exports (`CodexChatCLI replay`, `CodexChatCLI ledger export`)

## Rollout Plan

1. Treat this as a pre-merge local quality gate baseline.
2. Promote to hosted gate incrementally once CI budget allows.
3. Revisit targets after two release cycles of scorecard data.
