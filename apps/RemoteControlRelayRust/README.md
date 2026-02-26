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
- `POST /pair/stop`
- `POST /devices/list`
- `POST /devices/revoke`
- `GET /healthz`
- `GET /ws` (WebSocket)

## Notes

- This service is being developed as the production relay replacement for `apps/RemoteControlRelay`.
- Protocol compatibility remains `schemaVersion = 1`.
- Browser pairing routes are origin-gated and CORS-enabled for configured allowlisted origins.
- Request bodies are bounded by `MAX_JSON_BYTES` (default `65536`).
- WebSocket frames are bounded by `MAX_WS_MESSAGE_BYTES` (default `65536`).
- Remote mobile commands are throttled per device via `MAX_REMOTE_COMMANDS_PER_MINUTE` (default `240`).
- `thread.send_message` command text is bounded by `MAX_REMOTE_COMMAND_TEXT_BYTES` (default `16384`).
