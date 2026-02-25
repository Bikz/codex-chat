# Remote Control PWA (MVP)

Phone/web companion for Codex Chat remote control.

## Run locally

```bash
cd apps/RemoteControlPWA
pnpm start
```

Then open `http://localhost:4173`.

## Pairing flow

1. Desktop starts a remote session and shows QR link with `#sid=<session>&jt=<join_token>&relay=<relay_base_url>`.
2. PWA opens from that link and calls `POST /pair/join` on the relay.
3. Desktop must explicitly approve the pairing request in the Remote Control sheet.
4. Relay returns `deviceSessionToken` + `wsURL`.
5. PWA opens `wsURL`, then sends `{"type":"relay.auth","token":"<deviceSessionToken>"}`.
6. On websocket auth, relay rotates the device session token and the PWA stores the new token for reconnects.

## MVP behavior

- Two-pane mirror layout (projects + threads + active thread messages).
- Thread send command (`thread.send_message`) through websocket.
- Approval queue view with remote approve/decline commands when desktop enables remote approvals.
- Sequence tracking and gap detection.
- Manual + automatic snapshot requests on reconnect.
- Reconnect backoff when backgrounding or network drops.

## Limitations

- iOS/browser backgrounding can drop socket connections; PWA resumes with reconnect + snapshot.
