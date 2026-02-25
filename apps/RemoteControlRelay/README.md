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
- `POST /pair/join`: Mobile requests pairing; relay waits for explicit desktop approval, then issues a device session token.
- `GET /healthz`: Basic liveness and active session count.
- `GET /ws`: WebSocket channel for desktop/mobile routing.
  - Client authenticates immediately after connect with `{"type":"relay.auth","token":"..."}`.

## Security baseline (MVP)

- High-entropy opaque token validation (`[A-Za-z0-9_-]`, minimum length).
- One-time join token redemption.
- Desktop approval required for each join-token redemption attempt.
- Join-token expiry enforcement.
- Mobile websocket auth rotates the device session token on each successful connect.
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
- `PAIR_APPROVAL_TIMEOUT_MS` (default `45000`)
- `MAX_PENDING_JOIN_WAITERS` (default `64`)
- `WS_AUTH_TIMEOUT_MS` (default `10000`)
- `TOKEN_ROTATION_GRACE_MS` (default `15000`)
- `TRUST_PROXY` (`true` to honor `X-Forwarded-For`; default `false`)
- `ALLOW_LEGACY_QUERY_TOKEN_AUTH` (`true` to allow deprecated `?token=` websocket auth)
- `ALLOWED_ORIGINS` (comma-separated browser origin allowlist; defaults to relay origin plus local PWA dev origins)
