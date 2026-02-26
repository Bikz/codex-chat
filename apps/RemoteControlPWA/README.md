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
- Composer does not optimistically append outbound user messages; transcript updates render only after relay-confirmed events/snapshots.
- Outbound `thread.send_message` and `approval.respond` commands queue while offline and flush only after websocket re-auth succeeds.
- `Last synced` freshness tracking with stale-state indicator.
- Reconnect backoff when backgrounding or network drops.
- Foreground resume triggers an explicit snapshot resync when already connected.
- Sequence-gap handling requests snapshot resync without advancing local sequence state until a snapshot arrives.
- If desktop revokes the device, PWA stops auto-reconnect and requires re-pair.
- Relay validation/rate-limit/replay errors (including snapshot-request throttling) surface as explicit status messages with recovery hints.
- Relay load-shedding disconnects (for example `relay_over_capacity`) surface as explicit status messaging.

## Limitations

- iOS/browser backgrounding can drop socket connections; PWA resumes with reconnect + snapshot.
