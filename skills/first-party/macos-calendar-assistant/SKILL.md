---
name: macos-calendar-assistant
description: Use when the user explicitly wants calendar help on macOS. Enforces read-only-by-default workflow with explicit time-window clarification, event summary formatting, conflict detection, and permission-aware fallback behavior.
---

# macOS Calendar Assistant Workflow

## Overview

Use this skill for requests like:

- "what's on my calendar today?"
- "show my next 8 hours"
- "do I have conflicts this afternoon?"

This skill is read-only by default.

## Trigger Guard

Use this skill for personal scheduling requests.

If calendar phrasing appears inside engineering discussion (for example "calendar component"), confirm intent before running OS calendar lookup.

## Non-Negotiable Rules

1. Default to read-only operations.
2. Clarify time window before fetching if ambiguous.
3. Report timezone and time range used.
4. Never create/edit/delete events unless user explicitly asks in a separate step.
5. If permission is denied, provide concrete remediation steps.

## Required Inputs

- Time window:
  - today
  - next N hours
  - explicit date/time range
- Optional calendar filter (all calendars vs specific)

If window is missing, ask a concise follow-up.

## Execution Order

1. Clarify window and scope
- Ask follow-up only when needed:
  - "Do you want today or a custom range?"
  - "All calendars or specific ones?"

2. Fetch events (read-only)
- Prefer native action path when available: `calendar.today` with `rangeHours`.
- Otherwise use Apple Calendar fallback.

3. Normalize and sort
- Sort by start time ascending.
- Keep all-day events clearly marked.

4. Summarize for user
- Chronological bullet list:
  - title
  - start-end
  - calendar name
- Include:
  - conflicts/overlaps
  - free blocks (if requested or useful)

5. Ask follow-up intent
- Offer next step:
  - "Want me to check another range?"
  - "Want conflicts-only summary?"

## AppleScript Fallback (Read-Only)

```bash
/usr/bin/osascript <<'APPLESCRIPT'
set fromDate to current date
set toDate to fromDate + (24 * 60 * 60)
tell application "Calendar"
    set eventLines to {}
    repeat with cal in calendars
        set eventsInRange to (every event of cal whose start date >= fromDate and start date < toDate)
        repeat with e in eventsInRange
            set endDate to end date of e
            set titleText to summary of e
            set calName to name of cal
            set end of eventLines to (titleText & " :: " & (start date of e as text) & " -> " & (endDate as text) & " :: " & calName)
        end repeat
    end repeat
end tell
return eventLines as text
APPLESCRIPT
```

## Permission Denial Handling

If calendar access fails:

- Tell user exactly what happened.
- Provide path:
  - `System Settings > Privacy & Security > Calendars`
- Ask whether to retry after permission is granted.

## Output Contract

Always include:

1. Time window used.
2. Calendar scope used.
3. Event list in chronological order.
4. Conflict notes (if any).
5. Explicit note that operation was read-only.
