# Remote Control (MVP)

Remote Control lets a phone/web companion drive a local Codex Chat session without exposing Codex/OpenAI credentials outside the desktop boundary.

## Scope

This MVP delivers:

- Desktop remote-session surface (toolbar + sheet + QR link + stop session)
- In-session `Add Device` action that rotates join token without ending active remote session
- Secure pairing/session primitives in `CodexChatRemoteControl`
- Outbound-friendly relay service (`apps/RemoteControlRelayRust`)
- PWA companion with pairing, websocket reconnect, and sequence-gap snapshot requests (`apps/RemoteControlPWA`)
- Trusted-device list + revoke controls in desktop remote sheet

## Security model

- Desktop is the trust boundary for Codex/OpenAI credentials.
- Pairing uses high-entropy opaque tokens.
- Join tokens are short-lived and single-use.
- Desktop must explicitly approve each pairing request before the relay issues a mobile session token.
- Mobile session tokens rotate on every successful websocket authentication.
- Relay uses constant-time token comparison and strict token format validation.
- Pairing endpoints are rate-limited per client IP.
- Mobile command envelopes are validated and rate-limited per device and per session.
- Snapshot requests are rate-limited per device.
- Device connections per session are capped.
- Global websocket admission is capped.
- Per-socket outbound queues are bounded to enforce relay backpressure.
- Slow-consumer sockets are proactively disconnected (`reason: slow_consumer`) so clients reconnect and request a fresh snapshot instead of receiving stale partial streams.
- Relay logs avoid raw token output and truncate session identifiers.
- Sessions auto-expire through idle timeout and retention cleanup.

## Architecture

- `packages/CodexChatRemoteControl`
  - Versioned message schema (`RemoteControlEnvelope` + payloads)
  - Token/session descriptor generation and lease enforcement
  - Sequence tracker for gap/stale detection
  - Broker actor for session lifecycle and kill switch
- `apps/CodexChatApp`
  - Remote control toolbar entry and command-menu shortcut
  - `RemoteControlSheet` with QR code, copy link, and stop controls
  - `AppModel+RemoteControl` outbound websocket client, multi-thread snapshot + delta event streaming, and remote command ingestion
- `apps/RemoteControlRelayRust`
  - `POST /pair/start`, `POST /pair/join`, `POST /pair/refresh`, `POST /pair/stop`, `POST /devices/list`, `POST /devices/revoke`
  - `GET /healthz`, `GET /metricsz`, `GET /ws` (then `relay.auth` websocket message)
  - Pass-through websocket routing between desktop/mobile with payload validation and per-device/per-session command throttling
  - Per-device snapshot request throttling for reconnect abuse control
  - Runtime pressure and throughput counters on `/metricsz` (`outboundSendFailures`, `slowConsumerDisconnects`, plus `pairStart*` / `pairJoin*` / `pairRefresh*` / `wsAuth*`)
  - Optional Redis-backed runtime persistence (`REDIS_URL`, `REDIS_KEY_PREFIX`) for restart recovery
  - Optional NATS cross-instance routing (`NATS_URL`, `NATS_SUBJECT_PREFIX`) for stateless relay fanout
- `apps/RemoteControlPWA`
  - Pair via QR fragment (`#sid=...&jt=...&relay=...`)
  - Two-pane project/thread shell
  - Reconnect with backoff and snapshot re-request
  - Live event ingestion (`thread.message.append`, `turn.status.update`, approval refresh triggers)
  - Snapshot merge logic that preserves cached thread history and keeps per-thread memory bounded

## Local run

### 1) Start relay

```bash
cd apps/RemoteControlRelayRust
cargo run
```

Default URL: `http://localhost:8787`

### 2) Start PWA

```bash
cd apps/RemoteControlPWA
pnpm start
```

Default URL: `http://localhost:4173`

### 3) Point desktop app to local relay/PWA

Set environment variables before launching Codex Chat:

- `CODEXCHAT_REMOTE_CONTROL_JOIN_URL=http://localhost:4173`
- `CODEXCHAT_REMOTE_CONTROL_RELAY_WS_URL=ws://localhost:8787/ws`

### 4) Pair and connect

- In desktop app, open Remote Control and start a session.
- Scan the QR from phone (or open copied link).
- Tap Pair on PWA and wait for websocket connect.

## Known limitations

- Remote approvals are off by default and must be explicitly enabled in the desktop Remote Control sheet.
- iOS/PWA backgrounding can drop sockets; reconnect + snapshot is required.
- Desktop snapshot payloads are size-bounded for relay safety, so very large transcripts stream incrementally instead of all-at-once.

## Next hardening steps

- Multi-instance soak/load tests with Redis + NATS under reconnect churn.
- Manual relay load harness is available at `apps/RemoteControlRelayRust/tests/relay_load_harness.rs`, with wrappers `make remote-control-load`, `make remote-control-soak`, and `make remote-control-gate` (`make remote-control-load-gated` for one-shot load + gate). Gates enforce latency, backpressure, and websocket auth-failure budgets. Soak runs emit per-loop JSON artifacts and aggregate gate summary at `output/remote-control/relay-soak-summary.json`.
- OpenTelemetry metrics/tracing export and SLO alerting runbooks.
- Optional end-to-end payload encryption between desktop and phone.
- Passkey-based account option for multi-device identity over time.
- GKE deployment baseline is documented in `docs-public/REMOTE_CONTROL_GKE_DEPLOYMENT.md`.
- Relay incident/rollback operations are documented in `docs-public/REMOTE_CONTROL_RELAY_RUNBOOK.md`.
