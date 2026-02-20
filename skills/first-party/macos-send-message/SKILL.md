---
name: macos-send-message
description: Use when the user explicitly wants to send a text or iMessage from macOS. Enforces clarify-disambiguate-preview-confirm flow, contact verification, optional recency checks, and explicit send confirmation.
---

# macOS Send Message Workflow

## Overview

Use this skill for requests like:

- "send a message"
- "text Alex that I'm running late"
- "iMessage Sarah"

This skill is designed for safety and clarity. Do not silently send.

## Trigger Guard

Use this skill only when the user intent is personal messaging (SMS/iMessage/email-like chat).

If phrasing is ambiguous in a coding context (for example "send a message" while discussing app code), ask a one-line disambiguation question before running this workflow.

## Non-Negotiable Rules

1. Never send without an explicit final confirmation from the user.
2. Never guess a recipient when there are multiple matches.
3. Always show a draft preview before sending.
4. If contact resolution or recency verification is uncertain, say so and ask before continuing.
5. Keep the user informed in-chat at every step.

## Required Inputs

- Recipient (name or handle)
- Message body
- Preferred channel if relevant (iMessage/SMS)

If anything is missing, ask concise questions first.

## Execution Order

1. Clarify
- Ask for missing fields: recipient and exact message text.
- If user says "send a message" only, ask:
  - "Who should I message?"
  - "What should I say?"

2. Resolve contact
- Prefer read-only contact lookup before any send.
- Present candidates in numbered form when ambiguous.
- Ask user to choose one candidate explicitly.

3. Optional recency verification
- Attempt recent-thread check in Messages (if available).
- If recent-thread info is unavailable, tell the user recency could not be verified.

4. Draft preview
- Show:
  - Recipient display name
  - Destination handle (phone/email)
  - Service type (if known)
  - Exact message body
- Ask for explicit confirmation phrase: `send now`.

5. Send
- Prefer native action path when available: `messages.send`.
- If native path is unavailable, use AppleScript fallback.
- If anything changed after preview (recipient/body), regenerate preview.

6. Post-send summary
- Report success/failure in chat with timestamp and destination handle.
- If failed, include the actionable error and next step.

## Contact Lookup (Fallback Guidance)

Use `Contacts` for candidate matching when you need disambiguation.

Example fallback (AppleScript):

```bash
/usr/bin/osascript <<'APPLESCRIPT'
on run argv
    set queryText to item 1 of argv
    tell application "Contacts"
        set matches to every person whose name contains queryText
        set output to ""
        repeat with p in matches
            set personName to name of p
            set handleValue to ""
            try
                set handleValue to value of first phone of p
            end try
            if handleValue is "" then
                try
                    set handleValue to value of first email of p
                end try
            end if
            set output to output & personName & " :: " & handleValue & linefeed
        end repeat
    end tell
    return output
end run
APPLESCRIPT "Alex"
```

## Recent Contact Check (Best Effort)

- Try to verify recent conversation in `Messages`.
- Treat this as best-effort, not guaranteed.
- If unavailable, report: "I could not verify recent-message history on this system."

## Send Step (AppleScript Fallback)

Use only after explicit user confirmation:

```bash
/usr/bin/osascript -l AppleScript -e '
on run argv
    set targetHandle to item 1 of argv
    set messageText to item 2 of argv
    tell application "Messages"
        set targetService to first service whose service type = iMessage
        set targetBuddy to buddy targetHandle of targetService
        send messageText to targetBuddy
    end tell
end run' "recipient@handle" "message body"
```

## Failure Handling

- Permission denied:
  - Explain where to enable access:
  - `System Settings > Privacy & Security > Automation`
- Multiple contacts with same/similar name:
  - Ask user to choose by index.
- No valid handle found:
  - Ask user for exact number/email.

## Output Contract

Always provide:

1. What you resolved (recipient + handle).
2. The draft shown before send.
3. Whether send executed or not.
4. If sent, success summary with timestamp.
5. If not sent, clear reason and next action.
