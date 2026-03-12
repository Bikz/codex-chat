# ADR: Shared Codex Home Alignment

## Status

Accepted - 2026-03-11

## Context

CodexChat originally launched `codex app-server` with a CodexChat-managed runtime home under `~/CodexChat/global/codex-home` and selectively imported user artifacts from `~/.codex` into that managed copy. That design kept runtime state isolated from the rest of the Codex ecosystem, but it created a real product problem:

1. Users could authenticate in another Codex client and still appear signed out in CodexChat because the managed copy was stale.
2. Config drift could emerge between the shared `~/.codex/config.toml` and the managed runtime copy.
3. Support guidance became confusing because two different Codex homes existed on disk and only one of them was actually fresh.

The user expectation is straightforward: if they are already signed in through Codex CLI or another Codex client, CodexChat should pick up that same login automatically.

## Decision

CodexChat now treats the shared Codex home as canonical.

1. Active Codex home is `CODEX_HOME` from process environment when present, otherwise `~/.codex`.
2. Active agents home is `~/.agents`.
3. `~/CodexChat` remains the app-owned root for projects, metadata, diagnostics, and project-scoped `.agents/skills`.
4. Legacy managed homes under `~/CodexChat/global/codex-home` and `~/CodexChat/global/agents-home` are migration inputs only, not active runtime homes.
5. Startup performs a one-time safe handoff from the legacy managed homes into the active shared homes using copy-if-missing semantics only.
6. CodexChat no longer repairs, normalizes, quarantines, or deletes entries inside the live shared Codex home.
7. Manual storage actions are repurposed toward revealing the active shared home and archiving the old legacy managed copies after handoff succeeds.

## Consequences

### Positive

- CodexChat now shares authentication and config state with the rest of the Codex ecosystem.
- Users who already signed in through Codex CLI or another Codex client no longer need to re-authenticate just because CodexChat used a different home.
- Support guidance is clearer because Settings and Diagnostics can point directly at the active shared home and the handoff report.
- The app avoids touching live shared runtime caches, which reduces the risk of CodexChat damaging state it does not own.

### Costs

- CodexChat must treat active shared-home contents as external state and cannot rely on app-managed cleanup inside `~/.codex`.
- Legacy managed homes may continue to exist on disk until the user archives them.
- Storage docs and runbooks must clearly distinguish active shared homes from legacy managed migration sources.

## Follow-up

1. Keep Diagnostics and Storage settings aligned with the resolved active shared home path and handoff/archive reports.
2. Ensure contributor and support docs consistently tell users to inspect `CODEX_HOME` or `~/.codex`, not the old managed copy.
3. Preserve copy-if-missing handoff semantics unless a future migration introduces an explicit, user-reviewed merge strategy.
