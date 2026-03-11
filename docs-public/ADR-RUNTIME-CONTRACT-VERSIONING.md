# ADR: Runtime Contract Versioning And Compatibility Gating

## Status

Accepted - 2026-03-11

## Context

CodexChat talks to `codex app-server` over stdio JSON-RPC. That transport decision is correct and should remain the primary integration mode, but the runtime protocol surface is still evolving across Codex minor lines. Historically, CodexChat treated the installed `codex` binary on `PATH` as implicitly compatible and compensated for drift with error-string retries and partial decoding.

That posture created three concrete problems:

1. The client could not tell users whether the installed runtime was inside the support window it was actually tested against.
2. The runtime boundary was only partially typed, which made new request/event families future-fragile.
3. Unknown notifications and late protocol mismatches were hard to diagnose from user-provided artifacts.

## Decision

CodexChat adopts an explicit, repo-owned runtime compatibility model inside `CodexKit`.

1. Detect `codex --version` before launching `app-server`.
2. Evaluate that version against a checked-in compatibility matrix.
3. Select a protocol adapter from the detected version plus negotiated capabilities.
4. Start in `warn + degrade` mode when the runtime is outside the validated window instead of failing closed by default.
5. Treat stdio as the only first-class transport in this contract; websocket remains out of scope until the stdio boundary is stable.

The initial support window is:

- Validated: `0.114.x`
- Grace: `0.113.x`
- Outside that window: degraded / unsupported

Degraded mode means startup is allowed, but unsupported or experimental protocol features are visibly gated and recorded in diagnostics.

## Consequences

### Positive

- Runtime compatibility becomes explicit in Settings and diagnostics bundles.
- Contributor triage improves because support level, runtime version, and negotiated capabilities are captured as structured data.
- The runtime boundary can evolve through adapters rather than through unbounded request-time heuristics.
- Pending request cleanup can move toward authoritative runtime signals such as `serverRequest/resolved`.

### Costs

- The repo now owns a compatibility matrix and must update it intentionally as supported runtime lines change.
- New runtime features require typed modeling work before they are considered first-class in the UI.
- Temporary adapter overlap may exist while older heuristics are phased out.

## Follow-up

1. Add schema or golden-fixture coverage for each supported runtime line.
2. Keep diagnostics exports aligned with the compatibility snapshot and unknown-notification logging.
3. Expand typed request handling beyond approvals into permissions, user-input prompts, and MCP elicitation UX.
