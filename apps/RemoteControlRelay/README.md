# Remote Control Relay (MVP)

Minimal outbound-only relay for Codex Chat remote control.

## Run locally

```bash
cd apps/RemoteControlRelay
pnpm install
pnpm start
```

## Endpoints

- `POST /pair/start`: Desktop registers a one-time join token and desktop session token.
- `POST /pair/join`: Mobile redeems one-time join token and receives a device session token.
- `GET /healthz`: Basic liveness and active session count.
- `GET /ws?token=<session_token>`: WebSocket channel for desktop/mobile routing.

## Security baseline (MVP)

- High-entropy opaque token validation (`[A-Za-z0-9_-]`, minimum length).
- One-time join token redemption.
- Join-token expiry enforcement.
- Constant-time token equality checks.
- Per-IP rate limiting on pairing endpoints.
- Per-session mobile connection cap.
- Origin allowlist enforcement for browser pairing + mobile websocket clients.
- Idle timeout and retention-based cleanup.
- Non-sensitive logs (session IDs are truncated).

## Environment variables

- `PORT` (default `8787`)
- `HOST` (default `0.0.0.0`)
- `PUBLIC_BASE_URL` (default `http://localhost:<PORT>`)
- `MAX_JSON_BYTES` (default `65536`)
- `MAX_PAIR_REQUESTS_PER_MINUTE` (default `60`)
- `MAX_DEVICES_PER_SESSION` (default `2`)
- `SESSION_RETENTION_MS` (default `600000`)
- `ALLOWED_ORIGINS` (comma-separated browser origin allowlist; defaults to relay origin plus local PWA dev origins)
