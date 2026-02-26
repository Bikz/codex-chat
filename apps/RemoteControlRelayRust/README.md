# Remote Control Relay (Rust)

Rust implementation of the Codex Chat remote-control relay.

## Run locally

```bash
cd apps/RemoteControlRelayRust
cargo run
```

Default URL: `http://localhost:8787`

## Endpoints

- `POST /pair/start`
- `POST /pair/join`
- `POST /pair/refresh`
- `POST /pair/stop`
- `POST /devices/list`
- `POST /devices/revoke`
- `GET /healthz`
- `GET /metricsz`
- `GET /ws` (WebSocket)

## Notes

- This service is being developed as the production relay replacement for `apps/RemoteControlRelay`.
- Protocol compatibility remains `schemaVersion = 1`.
- Browser pairing routes are origin-gated and CORS-enabled for configured allowlisted origins.
- Request bodies are bounded by `MAX_JSON_BYTES` (default `65536`).
- WebSocket frames are bounded by `MAX_WS_MESSAGE_BYTES` (default `65536`).
- Per-socket outbound queues are bounded by `MAX_SOCKET_OUTBOUND_QUEUE` (default `256`) to avoid unbounded memory growth under slow clients.
- When a socket's outbound queue is saturated, relay forces a `disconnect` (`reason: slow_consumer`) so clients can reconnect and resync instead of silently dropping events.
- WebSocket admission can be bounded by `MAX_ACTIVE_WEBSOCKET_CONNECTIONS` (default `10000`).
- Remote mobile commands are throttled per device via `MAX_REMOTE_COMMANDS_PER_MINUTE` (default `240`).
- Remote mobile commands are also throttled per session via `MAX_REMOTE_SESSION_COMMANDS_PER_MINUTE` (default `480`).
- Snapshot re-sync requests are throttled per device via `MAX_SNAPSHOT_REQUESTS_PER_MINUTE` (default `60`).
- `thread.send_message` command text is bounded by `MAX_REMOTE_COMMAND_TEXT_BYTES` (default `16384`).
- Optional Redis durability can be enabled with `REDIS_URL` and `REDIS_KEY_PREFIX` (persisted per session key for restart recovery).
- Optional cross-instance fanout can be enabled with `NATS_URL` and `NATS_SUBJECT_PREFIX`.
- With Redis + NATS configured, relay instances can restore session metadata and route desktop/mobile websocket traffic across instances without exposing inbound desktop ports.
- `GET /metricsz` exposes live runtime counters for sessions, active websocket connections, token index size, and relay pressure indicators (including command/snapshot limiter buckets plus outbound send failures and slow-consumer disconnect counts).

## Manual load harness

Run the relay load harness (ignored by default in normal test runs):

```bash
make remote-control-load
```

Run repeated soak loops (uses `RELAY_SOAK_LOOPS`, default `5`):

```bash
RELAY_SOAK_LOOPS=10 make remote-control-soak
```

Equivalent direct command:

```bash
cd apps/RemoteControlRelayRust
RELAY_LOAD_SESSIONS=200 \
RELAY_LOAD_MESSAGES_PER_SESSION=20 \
RELAY_LOAD_SETUP_CONCURRENCY=32 \
RELAY_LOAD_ROUNDTRIP_TIMEOUT_MS=3000 \
RELAY_LOAD_P95_BUDGET_MS=1000 \
cargo test --test relay_load_harness relay_parallel_sessions_load_harness -- --ignored --nocapture
```

Environment variables:

- `RELAY_LOAD_SESSIONS` (default `50`)
- `RELAY_LOAD_MESSAGES_PER_SESSION` (default `10`)
- `RELAY_LOAD_SETUP_CONCURRENCY` (default `16`)
- `RELAY_LOAD_ROUNDTRIP_TIMEOUT_MS` (default `2000`)
- `RELAY_LOAD_P95_BUDGET_MS` (default `750`)
- `RELAY_LOAD_BASE_URL` (optional; when set, harness targets that relay instead of spawning local in-process relay)
- `RELAY_LOAD_ORIGIN` (default `http://localhost:4173`)
