#!/bin/sh
read _line
cat <<'JSON'
{"ok":true,"modsBar":{"title":"Calendar Assistant","markdown":"Read-only calendar checks for today or the next range.","scope":"thread","actions":[{"id":"calendar-today","label":"What's on my calendar today?","kind":"native.action","payload":{"rangeHours":"24"},"nativeActionID":"calendar.today","safetyLevel":"read-only","requiresConfirmation":false,"externallyVisible":false},{"id":"calendar-next-8h","label":"Next 8 hours","kind":"native.action","payload":{"rangeHours":"8"},"nativeActionID":"calendar.today","safetyLevel":"read-only","requiresConfirmation":false,"externallyVisible":false}]}}
JSON
