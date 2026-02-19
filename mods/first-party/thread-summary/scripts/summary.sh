#!/bin/sh
set -eu

MAX_LINES=40
input_file="$(mktemp "${TMPDIR:-/tmp}/codexchat-summary-input.XXXXXX")"

cleanup() {
  rm -f "$input_file"
}
trap cleanup EXIT

cat > "$input_file"

extract_raw() {
  /usr/bin/plutil -extract "$1" raw -o - "$input_file" 2>/dev/null || true
}

trim_value() {
  VALUE="$1" /usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import("Foundation");
var env = $.NSProcessInfo.processInfo.environment;
var raw = env.objectForKey("VALUE");
var value = raw ? String(ObjC.unwrap(raw)) : "";
value.trim();
JXA
}

json_escape() {
  VALUE="$1" /usr/bin/osascript -l JavaScript <<'JXA'
ObjC.import("Foundation");
var env = $.NSProcessInfo.processInfo.environment;
var raw = env.objectForKey("VALUE");
var value = raw ? String(ObjC.unwrap(raw)) : "";
JSON.stringify(value);
JXA
}

event="$(extract_raw event)"
thread_id="$(extract_raw thread.id)"

if [ -z "$thread_id" ]; then
  echo '{"ok":false,"log":"Missing thread id"}'
  exit 0
fi

state_dir=".codexchat/state"
mkdir -p "$state_dir"
summary_file="$state_dir/summary-$thread_id.md"

if [ "$event" = "turn.completed" ] || [ "$event" = "turn.failed" ]; then
  status="$(extract_raw payload.status)"
  if [ -z "$status" ]; then
    status="$event"
  fi
  error_text="$(trim_value "$(extract_raw payload.error)")"
  stamp="$(/bin/date -u +"%H:%M:%S")"
  line="- $stamp UTC | $status"
  if [ -n "$error_text" ]; then
    snippet="$(printf '%s' "$error_text" | /usr/bin/cut -c1-100)"
    line="$line | $snippet"
  fi

  next_file="$(mktemp "${TMPDIR:-/tmp}/codexchat-summary-next.XXXXXX")"
  {
    if [ -f "$summary_file" ]; then
      /usr/bin/awk 'NF { print }' "$summary_file"
    fi
    printf '%s\n' "$line"
  } | /usr/bin/tail -n "$MAX_LINES" > "$next_file"

  if [ -s "$next_file" ]; then
    /bin/mv "$next_file" "$summary_file"
  else
    rm -f "$next_file" "$summary_file"
  fi
elif [ "$event" = "modsBar.action" ]; then
  operation="$(extract_raw payload.operation)"
  if [ "$operation" = "clear" ]; then
    rm -f "$summary_file"
  fi
fi

markdown=""
if [ -f "$summary_file" ]; then
  markdown="$(cat "$summary_file")"
fi
if [ -z "$markdown" ]; then
  markdown="_No turns summarized yet._"
fi
escaped_markdown="$(json_escape "$markdown")"

printf '{"ok":true,"modsBar":{"title":"Thread Summary","scope":"thread","markdown":%s,"actions":[{"id":"summary-clear","label":"Clear Timeline","kind":"emitEvent","payload":{"operation":"clear","targetHookID":"summary-action"}}]}}\n' "$escaped_markdown"
