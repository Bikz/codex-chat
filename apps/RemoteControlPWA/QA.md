# Remote Control PWA QA Checklist

Use this checklist before cutting a release for the mobile web client.

## Pairing and auth

- Start a remote session in desktop, scan QR, and complete local desktop approval.
- Confirm PWA reaches `Connected` and shows home with project circles + chat list.
- Revoke the device from desktop and confirm PWA shows revoke state and stops auto reconnect.
- Stop the desktop session and confirm PWA shows stopped session message.

## Navigation and layout

- Confirm home route (`#view=home...`) shows project strip and chat list.
- Tap a chat row and confirm detail route updates to `#view=thread&tid=...` and back button returns to home.
- Use browser/hardware back from detail and confirm it returns to home view without exiting pairing state.
- Tap `View all` and confirm project sheet opens, focus stays inside sheet, and `Esc`/close button dismisses.

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
- Confirm long transcript messages (>8 lines or >480 chars) collapse by default and can be expanded/collapsed.

## Theme and readability

- In light mode, verify white-first surfaces with black text and neutral borders (no dark gradient/glass).
- In dark mode, verify black-first surfaces with white text and neutral borders (no blue gradient/glass).
- Switch system theme and confirm browser `theme-color` updates (`#ffffff` light, `#000000` dark).
