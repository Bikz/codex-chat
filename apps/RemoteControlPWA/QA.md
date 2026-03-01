# Remote Control PWA QA Checklist

Use this checklist before cutting a release for the mobile web client.

## Pairing and auth

- Start a remote session in desktop, scan QR, and complete local desktop approval.
- Confirm PWA reaches `Connected` and shows home with project circles + chat list.
- Confirm disconnected screen shows one pairing control surface (no duplicate pair/scan/paste controls in account sheet).
- From unauthenticated state, open `Scan QR` and confirm scanner sheet opens/closes with camera prompt.
- Verify `Paste Pair Link` imports `#sid` + `jt` payload and enables `Pair Device`.
- On iOS camera-opened browser flow, confirm `Copy Pair Link` guidance appears and copy action succeeds.
- Revoke the device from desktop and confirm PWA shows revoke state and stops auto reconnect.
- Stop the desktop session and confirm PWA shows stopped session message.

## Navigation and layout

- Confirm home route (`#view=home...`) shows project strip and chat list.
- Confirm project selector renders as a bounded 2-row grid and does not require horizontal swipe.
- Tap a chat row and confirm detail route updates to `#view=thread&tid=...` and back button returns to home.
- Use browser/hardware back from detail and confirm it returns to home view without exiting pairing state.
- Tap `View all` and confirm project sheet opens, focus stays inside sheet, and `Esc`/close button dismisses.

## Device matrix (required)

- iPhone Safari in-browser (portrait + landscape).
- iPhone Chrome in-browser (portrait + landscape).
- iPhone home-screen standalone mode (portrait + landscape).
- Android Chrome (portrait + landscape).
- Samsung Internet (portrait + landscape).

## Send and sync reliability

- While connected, send a message and confirm it appears only after relay-confirmed event/snapshot.
- Disconnect network on phone, send a message, and confirm UI reports queued command.
- Restore network and confirm queued command is flushed after websocket re-auth.
- Verify thread/project select actions do not queue while offline and show reconnect guidance.

## Background/resume (iOS + mobile browsers)

- Open a thread, background the PWA for 60+ seconds, then foreground.
- Confirm reconnect happens automatically if socket dropped.
- Confirm `Last synced` updates and no duplicate messages appear after resume.
- Force a sequence gap (restart relay or pause/resume network) and confirm snapshot resync recovers conversation state.
- While composer is focused with keyboard open, confirm the composer and send button remain visible above keyboard.
- Confirm transcript remains scrollable with keyboard open and no content is trapped below the composer.
- Confirm top and bottom controls respect safe-area spacing on notched/home-indicator devices.
- Confirm no page-level horizontal scroll in home or thread views (`scrollWidth` must match viewport width).

## Rotation and replay defenses

- Connect, then reconnect with old token and confirm relay rejects stale token.
- Confirm fresh token from `auth_ok` is accepted for subsequent reconnect.
- Send duplicate command sequence IDs and confirm relay returns replay rejection.

## UX and status messaging

- Confirm status banner shows clear states for:
  - pairing pending/approved
  - reconnect backoff
  - stale sync
  - queued commands
  - revoked/stopped session
- Confirm `Request Snapshot` recovers stale state without full re-pair.
- Confirm chat rows show `Running` / `New` / approval badges when corresponding state exists.
- Confirm chat row previews use user-visible content only (no raw IDs or transport payload text).
- Confirm transcript hides system transport events by default.
- Confirm long transcript messages (>8 lines or >480 chars) collapse by default and can be expanded/collapsed.
- Scroll up in a long thread, receive new message updates, and confirm transcript is not force-scrolled.
- Confirm `Jump to latest` appears when detached from bottom and returns to bottom when tapped.
- For long threads, confirm `Show older messages` reveals older transcript chunks without losing current reading position.
- Confirm command/diff-style messages render as collapsible cards and ambiguous text still renders as normal bubbles.
- Confirm reasoning state appears in top ambient status rail and is not rendered as transcript bubbles.
- Confirm composer auto-resizes while typing (up to cap) and `Cmd/Ctrl+Enter` sends while plain `Enter` adds a newline.

## Theme and readability

- In light mode, verify white-first surfaces with black text and neutral borders (no dark gradient/glass).
- In dark mode, verify black-first surfaces with white text and neutral borders (no blue gradient/glass).
- Switch system theme and confirm browser `theme-color` updates (`#ffffff` light, `#000000` dark).

## Automated test suite

- Run unit tests: `pnpm --filter @codexchat/remote-control-pwa test`.
- Run mobile E2E: `pnpm --filter @codexchat/remote-control-pwa test:e2e:mobile`.
- Confirm both Playwright projects pass:
  - `iphone-webkit`
  - `android-chrome`
