#!/bin/sh
set -eu

input_file="$(mktemp "${TMPDIR:-/tmp}/codexchat-notes-input.XXXXXX")"

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
note_file="$state_dir/notes-$thread_id.txt"

if [ "$event" = "modsBar.action" ]; then
  operation="$(extract_raw payload.operation)"
  case "$operation" in
    upsert)
      input_value="$(extract_raw payload.input)"
      trimmed_input="$(trim_value "$input_value")"
      if [ -z "$trimmed_input" ]; then
        rm -f "$note_file"
      else
        printf '%s\n' "$trimmed_input" > "$note_file"
      fi
      ;;
    clear)
      rm -f "$note_file"
      ;;
  esac
fi

note=""
if [ -f "$note_file" ]; then
  note="$(cat "$note_file")"
fi
note="$(trim_value "$note")"

markdown="$note"
if [ -z "$markdown" ]; then
  markdown="_Start typing to save thread-specific notes. Notes autosave for this chat._"
fi
escaped_markdown="$(json_escape "$markdown")"

printf '{"ok":true,"modsBar":{"title":"Personal Notes","scope":"thread","markdown":%s,"actions":[{"id":"notes-add-edit","label":"Add / Edit Note","kind":"promptThenEmitEvent","payload":{"operation":"upsert","targetHookID":"notes-action"},"prompt":{"title":"Personal Notes","message":"Write a note for this thread.","placeholder":"Next steps, key commands, reminders..."}},{"id":"notes-clear","label":"Clear Note","kind":"emitEvent","payload":{"operation":"clear","targetHookID":"notes-action"}}]}}\n' "$escaped_markdown"
