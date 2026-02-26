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
- Remote mobile commands are throttled per device via `MAX_REMOTE_COMMANDS_PER_MINUTE` (default `240`).
- `thread.send_message` command text is bounded by `MAX_REMOTE_COMMAND_TEXT_BYTES` (default `16384`).
- Optional Redis durability can be enabled with `REDIS_URL` and `REDIS_KEY_PREFIX` (persisted per session key for restart recovery).
- Optional cross-instance fanout can be enabled with `NATS_URL` and `NATS_SUBJECT_PREFIX`.
- With Redis + NATS configured, relay instances can restore session metadata and route desktop/mobile websocket traffic across instances without exposing inbound desktop ports.
- `GET /metricsz` exposes live runtime counters for sessions, active websocket connections, token index size, and relay pressure indicators.
