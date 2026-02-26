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
   - Join payload includes a best-effort `deviceName` inferred from the browser/device.
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
- Live delta event handling for message appends and turn status updates.
- `Last synced` freshness tracking with stale-state indicator.
- Reconnect backoff when backgrounding or network drops.
- Foreground resume triggers an explicit snapshot resync when already connected.
- If desktop revokes the device, PWA stops auto-reconnect and requires re-pair.

## Limitations

- iOS/browser backgrounding can drop socket connections; PWA resumes with reconnect + snapshot.
