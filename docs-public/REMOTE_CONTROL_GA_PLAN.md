# Remote Control GA Plan (10k Users)

Status: Approved execution plan (GKE + Rust relay + Redis + NATS JetStream)
Date: 2026-02-26

## North Star

Launch Remote Control to GA with production reliability/security for 10k concurrent users while preserving CodexChat's local-trust boundary (desktop owns runtime + credentials).

## Locked Architecture Decisions

- Relay implementation: Rust (`apps/RemoteControlRelayRust`) replacing Node relay for production.
- Runtime model: stateless relay instances behind Kubernetes service + external load balancer.
- Stateful dependencies:
  - Redis: authoritative session/token/device/rate-limit state.
  - NATS JetStream: cross-instance routing and reliable event fanout.
- Platform: GKE (Autopilot) on GCP.
- Desktop remains trust boundary; no Codex/OpenAI auth material leaves desktop.
- Protocol compatibility: keep `schemaVersion = 1` while migrating.

## Milestones

- M1: Epic A complete (Rust relay parity + compatibility suite).
- M2: Epics B/C complete (trusted devices + durable horizontal architecture).
- M3: Epics D/E complete (security hardening + deterministic reliability harness).
- M4: Epics F/G/H complete (mobile UX reliability + policy + SLO/load proof).
- M5: Epics I/J complete (production infra + staged rollout to GA).

## Epic A: Rust Relay Parity (P0)

Goal: replace Node relay with Rust relay that is wire-compatible for desktop and PWA.

User stories:
- As a desktop app, I can start a remote session and register pairing metadata with relay.
- As a mobile PWA, I can pair with a one-time join token and receive a device session token.
- As desktop/mobile clients, I can authenticate websocket connections and exchange envelopes.
- As a user, reconnect does not require changing app clients during migration.

Scope:
- Build Rust relay with endpoints:
  - `POST /pair/start`
  - `POST /pair/join`
  - `GET /healthz`
  - `GET /ws` + `relay.auth`
- Preserve current messages/signals:
  - `auth_ok`, `relay.device_count`, `relay.snapshot_request`, `relay.pair_request`, `relay.pair_result`.
- Preserve token rotation behavior on mobile websocket auth.
- Add compatibility tests that run the same scenarios against Node and Rust relays.

Implemented so far (2026-02-26):
- Added cross-relay compatibility harness at `apps/RemoteControlRelay/test/relay.compat.test.mjs`.
- Local gate command available via `make remote-control-compat` (`pnpm -s run remote:relay:compat`).
- Harness runs the same normalized scenario (pair start/join + desktop approval, token rotation, anti-spoof forwarding checks, stale-token rejection) against both Node and Rust relays and fails on behavioral drift.
- Contributor smoke checks now run the compatibility harness by default via `scripts/oss-smoke.sh` (override with `OSS_SMOKE_SKIP_REMOTE_CONTROL_COMPAT=1` when intentionally bypassing).

Acceptance criteria:
- Desktop + PWA work unchanged against Rust relay in local/staging.
- Existing relay integration scenarios pass against Rust.
- Protocol mismatch regressions are caught by CI.

Tests:
- Unit: token validation, constant-time compare wrappers, envelope parsing.
- Integration: pair start/join, desktop approval gate, token rotation, metadata anti-spoofing.
- Compatibility: golden scenario assertions across Node vs Rust outputs.

## Epic B: Trusted Device Management (P0)

Goal: explicit trusted device lifecycle with instant revoke.

User stories:
- As a user, I can see all paired devices with last-seen/activity.
- As a user, I can revoke a device and force disconnect immediately.
- As a revoked device, I cannot reconnect with prior token(s).

Scope:
- Relay APIs/events:
  - list devices for session
  - revoke device
  - force disconnect active socket
- Desktop sheet UI:
  - trusted device list
  - revoke action + confirmation
- PWA:
  - revoked-session state + re-pair guidance

Acceptance criteria:
- Revoke action takes effect within 1s for active sockets.
- Revoked device token/auth cannot be reused.
- Device state remains consistent across relay instances.

Tests:
- Unit: revoke state transitions.
- Integration: active disconnect + reconnect denial.
- UI: desktop flow to list/revoke device.

## Epic C: Relay Durability + Horizontal Readiness (P0)

Goal: remove in-memory session coupling and support multi-instance scale safely.

User stories:
- As a user, my active session survives relay pod restart/failover.
- As a platform, any relay instance can process any request consistently.

Scope:
- Redis-backed authoritative state for:
  - sessions, join-token lease, devices, token index, pending pair requests, presence heartbeat, idle/retention timestamps.
- NATS JetStream subjects for routing between desktop/mobile connections across instances.
- Leaderless relay instance behavior (no sticky requirement).

Acceptance criteria:
- Pod restart does not silently orphan sessions.
- Cross-instance routing works under random pod churn.
- Behavior is deterministic/documented.

Tests:
- Integration: multi-instance join/command flow.
- Chaos: pod kill during active sessions.
- Persistence: state recovery assertions.

## Epic D: Security Hardening Sweep (P0)

Goal: close high-impact abuse paths.

User stories:
- As a user, my session cannot be hijacked by replay/spoof/flood attempts.
- As an operator, logs contain actionable telemetry without secrets.

Scope:
- Strict payload schema validation for all websocket messages.
- Replay protections:
  - bounded sequence windows
  - nonce/command id dedupe where applicable.
- Per-session/device rate limits and command throttle policies.
- Strong origin/session binding and websocket auth timeout enforcement.
- Audit-safe structured logging and PII minimization.

Acceptance criteria:
- Threat checklist has no open critical/high findings.
- Security controls are test-covered and enforced in code.

Tests:
- Negative/fuzz tests for malformed payloads.
- Replay + flood tests.
- Log snapshot tests for redaction.

## Epic E: End-to-End Reliability Harness (P0)

Goal: deterministic suite that covers real remote-control journeys.

User stories:
- As a maintainer, I can catch protocol/reconnect regressions locally before release.

Scope:
- Full-path deterministic fixture:
  - session start -> pair approval -> thread select/send -> turn updates -> approval response -> reconnect with rotated token.
- Chaos suite:
  - dropped websocket
  - delayed snapshot
  - sequence gaps
  - reconnect churn
  - relay pod restart.

Acceptance criteria:
- Suite is deterministic in local CI.
- Required gate before staging/prod promotion.

Tests:
- Integration harness scripts + CI target.

## Epic F: Mobile Reliability UX (P1)

Goal: clear reconnection/resync behavior in browser/PWA lifecycle transitions.

User stories:
- As a mobile user, I can tell if I am stale/disconnected and recover quickly.

Scope:
- PWA status upgrades:
  - `Last synced`
  - reconnect state
  - explicit `Resync now` action
  - stale thread indication.
- Optional web push for approval-required/turn-complete notifications.

Acceptance criteria:
- No dead-end state after background/resume.
- Users can always recover from stale connection within one action.

Tests:
- PWA integration tests for visibility-change reconnect and manual resync.

## Epic G: Multi-Device Policy Clarification (P1)

Goal: explicit product policy and enforcement.

User stories:
- As a user, I understand how many devices are allowed and how to add one safely.

Scope:
- GA policy (proposed): up to 2 trusted devices per session.
- Desktop `Add device` flow generating fresh short-lived join token.
- Relay policy enforcement + user-facing errors.
- Docs update across install and security model.

Acceptance criteria:
- Policy is visible in UI/docs and enforced consistently.

Tests:
- Policy enforcement integration tests.

## Epic H: Observability + Load + Backpressure (P0)

Goal: prove and maintain 10k readiness.

User stories:
- As an operator, I can detect and act on degradation before users are impacted.

Scope:
- OpenTelemetry traces/metrics/logs for relay.
- Dashboards + alerts for SLOs:
  - pairing latency
  - command roundtrip latency
  - websocket auth failures
  - reconnect recovery success
  - Redis/NATS lag + saturation.
- Load testing to 10k concurrent users equivalent (20k sockets).
- Backpressure behavior under overload with clear client signals.

Implemented so far (2026-02-26):
- Relay enforces bounded outbound websocket queues with explicit slow-consumer disconnects.
- `/metricsz` now includes backpressure counters:
  - `outboundSendFailures`
  - `slowConsumerDisconnects`
- `/metricsz` now includes pairing/auth throughput counters:
  - `pairStart*`, `pairJoin*`, `pairRefresh*`
  - `wsAuth*`
- Manual load harness exists in `apps/RemoteControlRelayRust/tests/relay_load_harness.rs`.
- Local wrappers are available:
  - `make remote-control-load`
  - `make remote-control-soak`
  - `make remote-control-gate`
  - `make remote-control-load-gated`
- Soak wrapper now writes per-loop load artifacts plus an aggregate summary gate output at `output/remote-control/relay-soak-summary.json`.
- Load/soak gates now include websocket auth-failure budgets in addition to latency and backpressure thresholds.

Acceptance criteria:
- 24h soak test meets defined SLO thresholds.
- Error budget burn alerts and runbooks validated.

Tests:
- Load scripts + performance assertions in pipeline.

## Epic I: Production Platform (GKE) (P0)

Goal: secure, scalable production deployment foundation.

User stories:
- As an operator, I can deploy safely, roll back quickly, and recover from zone failures.

Scope:
- GKE deployment with:
  - HPA + PDB + anti-affinity
  - rolling/canary deployment strategy
  - secret management
  - WAF/rate controls
  - TLS termination.
- Managed Redis and managed NATS (or highly-available NATS cluster).
- Runbooks: incident response, rollback, disaster recovery.

Implemented so far (2026-02-26):
- Added baseline GKE manifests under `infra/remote-control-relay/gke`:
  - namespace, service account, config/secret templates
  - deployment, service, HPA, PDB
- Added rollout overlays for `staging` and `prod-canary`.
- Added deployment guide: `docs-public/REMOTE_CONTROL_GKE_DEPLOYMENT.md`.
- Added relay operations runbook: `docs-public/REMOTE_CONTROL_RELAY_RUNBOOK.md`.

Acceptance criteria:
- Multi-zone failure exercises pass.
- Canary + rollback tested in staging/prod.

Tests:
- Infra validation scripts and game-day checklists.

## Epic J: Rollout to GA (P0)

Goal: staged release with strict gates.

User stories:
- As a user, I experience stable remote control across pairing, live updates, and reconnect flows.

Scope:
- Rollout phases:
  - internal dogfood
  - private beta
  - public beta
  - GA.
- Stage gates by SLO + security + support readiness.
- Launch docs/support playbooks.

Implemented so far (2026-02-26):
- Added local stage-gate automation script `scripts/remote-control-stage-gate.sh`.
- Stage gate checks now validate:
  - Node-vs-Rust compatibility gate status
  - load artifact status and budgets
  - soak summary status and failure counts
  - GKE manifest validation preflight

Acceptance criteria:
- Two consecutive weeks of stable beta SLOs.
- No open critical launch blockers.

Tests:
- Stage gate validation checklist executed before each promotion.

## Post-GA Optional Epics

### Epic K: Optional Account/Passkey Mode (P2)
- Add passkey account layer while preserving accountless pairing mode.

### Epic L: Optional End-to-End Payload Encryption (P2)
- App-level E2EE channel desktop <-> PWA; relay routes ciphertext only.

## Program-Level Risks

- Message semantics drift during Node->Rust cutover.
- Cross-instance ordering assumptions causing stale UI/update races.
- Redis/NATS operational complexity under burst reconnect storms.
- PWA background behavior differences across iOS versions.

Mitigations:
- Compatibility harness first.
- Deterministic sequence/replay policy with explicit docs.
- Load + chaos testing before GA.
- Feature flags for progressive rollout.

## Definition of Done (GA)

- Epics A through J completed.
- Security hardening checklist signed off.
- 10k equivalent load and 24h soak pass.
- Runbooks, dashboards, and on-call processes validated.
- Desktop, relay, and PWA docs updated and versioned.
