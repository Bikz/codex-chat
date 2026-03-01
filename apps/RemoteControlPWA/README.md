# Remote Control PWA (Next.js)

Mobile/web companion for Codex Chat remote control.

## Stack

- Next.js App Router + TypeScript
- Tailwind + shadcn/Radix primitives
- Zustand state store
- Playwright mobile E2E + Vitest unit tests

## Run locally

```bash
cd apps/RemoteControlPWA
pnpm dev
```

Then open `http://localhost:4173`.

## Production build

```bash
cd apps/RemoteControlPWA
pnpm build
pnpm start
```

## Run tests

Unit tests:

```bash
cd apps/RemoteControlPWA
pnpm test
```

Mobile E2E tests:

```bash
cd apps/RemoteControlPWA
pnpm test:e2e:mobile
```

Optional headed run:

```bash
cd apps/RemoteControlPWA
pnpm test:e2e:mobile:headed
```

## Pairing flow

1. Desktop starts a remote session and shows QR link with `#sid=<session>&jt=<join_token>&relay=<relay_base_url>`.
2. PWA opens from that link and calls `POST /pair/join` on the relay.
   - Join payload includes a best-effort `deviceName` inferred from the browser/device.
   - Landing from QR shows a welcome/install card to encourage home-screen install before pairing.
   - If phone camera opens the link in browser first, the UI now provides `Copy Pair Link` + `Paste Pair Link` handoff guidance for the installed app.
3. You can also scan directly in the PWA via `Scan QR` (camera) or import via `Paste Pair Link`.
4. Desktop must explicitly approve the pairing request in the Remote Control sheet.
5. Relay returns `deviceSessionToken` + `wsURL`.
6. PWA opens `wsURL`, then sends `{"type":"relay.auth","token":"<deviceSessionToken>"}`.
7. On websocket auth, relay rotates the device session token and the PWA stores the new token for reconnects.
8. Paired-device credentials persist in browser storage so the PWA can reconnect automatically after app/browser relaunch until desktop revokes or ends the session.

## Navigation contract

Hash-based route contract is preserved:

- `#view=home&pid=<project-id|all>`
- `#view=thread&tid=<thread-id>&pid=<project-id|all>`

This keeps browser/hardware back behavior aligned with home/detail navigation.

## UI contract

- Single-page conversation-first layout (home list + focused chat detail + back navigation).
- Project circles on home (`All` + top projects + `View all`) with per-project chat filtering.
- Account sheet contains pairing/session controls.
- Inline approval indicators on chat rows and in-chat approval tray actions.
- Message wrapping and long-message collapse/expand in transcript view.
- Smart transcript anchoring: auto-follow only when already near the bottom.
- Floating `Jump to latest` button when new messages arrive while reading older content.
- Progressive transcript rendering (`Show older messages`) for very long threads.
- Specialized transcript cards for command execution, diffs, and reasoning summaries with safe plain-text fallback.
- Composer auto-resize with `Cmd/Ctrl+Enter` send shortcut and dispatching state indicator.

## Mobile hardening guarantees

- safe-area-aware spacing (`env(safe-area-inset-*)`) for notch/home-indicator devices
- dynamic viewport sizing with keyboard-aware composer offset via `visualViewport` when available
- fallback sticky behavior when `visualViewport` is unavailable
- touch-target minimum sizing on primary actions
- in-app QR scanner sheet (camera + manual/clipboard fallback)

## Reliability guarantees (unchanged protocol behavior)

- Thread send command (`thread.send_message`) through websocket.
- Sequence tracking and gap detection.
- Manual + automatic snapshot requests on reconnect.
- Live delta event handling for message appends and turn status updates.
- Composer does not optimistically append outbound user messages; transcript updates render only after relay-confirmed events/snapshots.
- Outbound `thread.send_message` and `approval.respond` commands queue while offline and flush only after websocket re-auth succeeds.
- Reconnect backoff when backgrounding or network drops.
- Saved paired-device credentials auto-restore on launch and trigger reconnect without rescanning QR.
- `Forget This Device` clears locally saved pairing credentials.
- Relay validation/rate-limit/replay errors surface as explicit status messages.

## Limitations

- iOS/browser backgrounding can drop socket connections; PWA resumes with reconnect + snapshot.
- iOS does not reliably deep-link a scanned HTTPS QR directly into an installed PWA instance. Browser-opened links require manual handoff (`Copy Pair Link` in browser, then `Paste Pair Link` in installed app), or scanning directly from inside the installed app.

## QA

- Manual release checklist: [`QA.md`](./QA.md)
