#!/bin/sh
read _line
cat <<'JSON'
{"ok":true,"modsBar":{"title":"Desktop Cleanup","markdown":"Preview-only cleanup groups desktop files into folders before any move runs.","scope":"thread","actions":[{"id":"desktop-cleanup-run","label":"Preview Cleanup","kind":"native.action","payload":{},"nativeActionID":"desktop.cleanup","safetyLevel":"destructive","requiresConfirmation":true,"externallyVisible":false}]}}
JSON
