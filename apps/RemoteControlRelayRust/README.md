# Remote Control Relay (Rust)

Rust implementation of the Codex Chat remote-control relay.

## Run locally

```bash
cd apps/RemoteControlRelayRust
cargo run
```

Default URL: `http://localhost:8787`

## Container build

```bash
cd apps/RemoteControlRelayRust
docker build -t remote-control-relay-rust:local .
docker run --rm -p 8787:8787 remote-control-relay-rust:local
```

Validate the production GKE bundle:

```bash
make remote-control-gke-validate
```

Run Node-vs-Rust protocol compatibility scenario:

```bash
make remote-control-compat
```

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
- `GET /metricsz` exposes live runtime counters for sessions, active websocket connections, token index size, pairing/auth throughput (`pairStart*`, `pairJoin*`, `pairRefresh*`, `wsAuth*`), and relay pressure indicators (including command/snapshot limiter buckets plus outbound send failures and slow-consumer disconnect counts).

## Manual load harness

Run the relay load harness (ignored by default in normal test runs):

```bash
make remote-control-load
```

Run repeated soak loops (uses `RELAY_SOAK_LOOPS`, default `5`):

```bash
RELAY_SOAK_LOOPS=10 make remote-control-soak
```

The soak wrapper writes per-loop artifacts and an aggregate summary:

- per-loop results: `output/remote-control/soak-runs/loop-<n>.json`
- summary: `output/remote-control/relay-soak-summary.json`

Evaluate the latest load artifact against gate thresholds:

```bash
make remote-control-gate
```

Run load harness and enforce gate in one step:

```bash
make remote-control-load-gated
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
- `RELAY_LOAD_RESULTS_PATH` (default `output/remote-control/relay-load-result.json`; writes machine-readable JSON summary for each run)
- `RELAY_GATE_RESULTS_PATH` (default `output/remote-control/relay-load-result.json`; path the gate script reads)
- `RELAY_GATE_REQUIRE_STATUS` (default `ok`)
- `RELAY_GATE_MAX_P95_US` (optional; enforces microsecond p95 gate when provided)
- `RELAY_GATE_MAX_P95_MS` (optional; overrides JSON budget when provided)
- `RELAY_GATE_MAX_ERRORS` (default `0`)
- `RELAY_GATE_MAX_OUTBOUND_SEND_FAILURES` (default `0`)
- `RELAY_GATE_MAX_SLOW_CONSUMER_DISCONNECTS` (default `0`)
- `RELAY_GATE_MAX_WS_AUTH_FAILURES` (default `0`)
- `RELAY_GATE_MIN_SAMPLE_COUNT` (default `1`)
- `RELAY_SOAK_LOOPS` (default `5`)
- `RELAY_SOAK_RESULTS_DIR` (default `output/remote-control/soak-runs`)
- `RELAY_SOAK_SUMMARY_PATH` (default `output/remote-control/relay-soak-summary.json`)
- `RELAY_SOAK_MAX_FAILING_LOOPS` (default `0`)
- `RELAY_SOAK_MAX_P95_US` (optional)
- `RELAY_SOAK_MAX_P95_MS` (optional)
- `RELAY_SOAK_MAX_TOTAL_ERRORS` (default `0`)
- `RELAY_SOAK_MAX_TOTAL_OUTBOUND_SEND_FAILURES` (default `0`)
- `RELAY_SOAK_MAX_TOTAL_SLOW_CONSUMER_DISCONNECTS` (default `0`)
- `RELAY_SOAK_MAX_TOTAL_WS_AUTH_FAILURES` (default `0`)
- `RELAY_SOAK_MIN_TOTAL_SAMPLES` (default `1`)
