# Remote Control PWA (MVP)

Phone/web companion for Codex Chat remote control.

## Run locally

```bash
cd apps/RemoteControlPWA
pnpm start
```

Then open `http://localhost:4173`.

## Pairing flow

1. Desktop starts a remote session and shows QR link with `#sid=<session>&jt=<join_token>`.
2. PWA opens from that link and calls `POST /pair/join` on the relay.
3. Relay returns `deviceSessionToken` + `wsURL`.
4. PWA opens `wsURL?token=<deviceSessionToken>`.

## MVP behavior

- Two-pane mirror layout (projects + threads + active thread messages).
- Thread send command (`thread.send_message`) through websocket.
- Sequence tracking and gap detection.
- Manual + automatic snapshot requests on reconnect.
- Reconnect backoff when backgrounding or network drops.

## Limitations

- Desktop-side broker websocket streaming is scaffolded; full event parity depends on next integration steps.
- iOS/browser backgrounding can drop socket connections; PWA resumes with reconnect + snapshot.
