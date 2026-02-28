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
   - Landing from QR shows a welcome/install card to encourage home-screen install before pairing.
3. Desktop must explicitly approve the pairing request in the Remote Control sheet.
4. Relay returns `deviceSessionToken` + `wsURL`.
5. PWA opens `wsURL`, then sends `{"type":"relay.auth","token":"<deviceSessionToken>"}`.
6. On websocket auth, relay rotates the device session token and the PWA stores the new token for reconnects.
7. Paired-device credentials persist in browser storage so the PWA can reconnect automatically after app/browser relaunch until desktop revokes or ends the session.

## MVP behavior

- Single-page conversation-first layout (home list + focused chat detail + back navigation).
- Project circles on home (`All` + top projects + `View all`) with per-project chat filtering.
- Hash-based navigation contract:
  - `#view=home&pid=<project-id|all>`
  - `#view=thread&tid=<thread-id>&pid=<project-id|all>`
- Thread send command (`thread.send_message`) through websocket.
- Inline approval indicators on chat rows and in-chat approval tray actions when desktop enables remote approvals.
- Sequence tracking and gap detection.
- Manual + automatic snapshot requests on reconnect.
- Live delta event handling for message appends and turn status updates.
- Message wrapping and long-message collapse/expand in transcript view.
- Composer does not optimistically append outbound user messages; transcript updates render only after relay-confirmed events/snapshots.
- Outbound `thread.send_message` and `approval.respond` commands queue while offline and flush only after websocket re-auth succeeds.
- `Last synced` freshness tracking with stale-state indicator.
- Reconnect backoff when backgrounding or network drops.
- Foreground resume triggers an explicit snapshot resync when already connected.
- Saved paired-device credentials auto-restore on launch and trigger reconnect without rescanning QR.
- Dedicated "Forget This Device" control clears locally saved pairing credentials.
- Sequence-gap handling requests snapshot resync without advancing local sequence state until a snapshot arrives.
- If desktop revokes the device, PWA stops auto-reconnect and requires re-pair.
- Relay validation/rate-limit/replay errors (including snapshot-request throttling) surface as explicit status messages with recovery hints.
- Relay load-shedding disconnects (for example `relay_over_capacity`) surface as explicit status messaging.

## Limitations

- iOS/browser backgrounding can drop socket connections; PWA resumes with reconnect + snapshot.

## QA

- Manual release checklist: [`QA.md`](./QA.md)
