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
- `GET /healthz`
- `GET /ws` (WebSocket)

## Notes

- This service is being developed as the production relay replacement for `apps/RemoteControlRelay`.
- Protocol compatibility remains `schemaVersion = 1`.
