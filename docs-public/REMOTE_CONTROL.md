# Remote Control (MVP)

Remote Control lets a phone/web companion drive a local Codex Chat session without exposing Codex/OpenAI credentials outside the desktop boundary.

## Scope

This MVP delivers:

- Desktop remote-session surface (toolbar + sheet + QR link + stop session)
- Secure pairing/session primitives in `CodexChatRemoteControl`
- Outbound-friendly relay service (`apps/RemoteControlRelay`)
- PWA companion with pairing, websocket reconnect, and sequence-gap snapshot requests (`apps/RemoteControlPWA`)

## Security model

- Desktop is the trust boundary for Codex/OpenAI credentials.
- Pairing uses high-entropy opaque tokens.
- Join tokens are short-lived and single-use.
- Desktop must explicitly approve each pairing request before the relay issues a mobile session token.
- Mobile session tokens rotate on every successful websocket authentication.
- Relay uses constant-time token comparison and strict token format validation.
- Pairing endpoints are rate-limited per client IP.
- Device connections per session are capped.
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
  - `AppModel+RemoteControl` outbound websocket client, snapshot + delta event streaming, and remote command ingestion
- `apps/RemoteControlRelay`
  - `POST /pair/start`, `POST /pair/join`, `GET /healthz`, `GET /ws` (then `relay.auth` websocket message)
  - Pass-through websocket routing between desktop/mobile
- `apps/RemoteControlPWA`
  - Pair via QR fragment (`#sid=...&jt=...&relay=...`)
  - Two-pane project/thread shell
  - Reconnect with backoff and snapshot re-request
  - Live event ingestion (`thread.message.append`, `turn.status.update`, approval refresh triggers)

## Local run

### 1) Start relay

```bash
cd apps/RemoteControlRelay
pnpm install
pnpm start
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
- Relay state is in-memory (no persistent store yet).

## Next hardening steps

- Device revocation list and explicit trusted-device management.
- Optional end-to-end payload encryption between desktop and phone.
- Passkey-based account option for multi-device identity over time.
