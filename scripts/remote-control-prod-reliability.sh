#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ARTIFACT_ROOT="${REMOTE_RELIABILITY_ARTIFACT_ROOT:-$REPO_ROOT/output/remote-control/prod-e2e}"
TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
RUN_DIR="${REMOTE_RELIABILITY_RUN_DIR:-$ARTIFACT_ROOT/$TIMESTAMP}"
HARNESS_LOG="$RUN_DIR/harness.log"
BROWSER_LOG="$RUN_DIR/browser.log"
SUMMARY_PATH="${REMOTE_RELIABILITY_SUMMARY_PATH:-$RUN_DIR/summary.json}"
PLAYWRIGHT_NODE_MODULES="${REMOTE_RELIABILITY_PLAYWRIGHT_NODE_MODULES:-$REPO_ROOT/apps/RemoteControlPWA/node_modules}"
NO_GAP_DETECTED="${REMOTE_RELIABILITY_REQUIRE_NO_GAP_DETECTED:-1}"

mkdir -p "$RUN_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command missing: $1" >&2
    exit 1
  fi
}

cleanup() {
  if [[ -n "${HARNESS_PID:-}" ]] && kill -0 "$HARNESS_PID" >/dev/null 2>&1; then
    kill -INT "$HARNESS_PID" >/dev/null 2>&1 || true
    wait "$HARNESS_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

require_command node
require_command python3

if [[ ! -f "$PLAYWRIGHT_NODE_MODULES/@playwright/test/package.json" ]]; then
  echo "error: missing Playwright dependency at $PLAYWRIGHT_NODE_MODULES/@playwright/test/package.json" >&2
  exit 1
fi

node "$REPO_ROOT/scripts/remote-control-prod-reliability-harness.mjs" >"$HARNESS_LOG" 2>&1 &
HARNESS_PID=$!

JOIN_URL=""
for _ in $(seq 1 60); do
  JOIN_URL="$(python3 - "$HARNESS_LOG" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.exists():
    print("")
    raise SystemExit(0)

for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
    line = line.strip()
    if not line:
        continue
    try:
        payload = json.loads(line)
    except json.JSONDecodeError:
        continue
    if payload.get("kind") == "session_started":
        print(payload.get("joinURL", ""))
        raise SystemExit(0)
print("")
PY
)"
  if [[ -n "$JOIN_URL" ]]; then
    break
  fi
  sleep 1
done

if [[ -z "$JOIN_URL" ]]; then
  echo "error: failed to discover join URL from harness log" >&2
  exit 1
fi

NODE_PATH="$PLAYWRIGHT_NODE_MODULES" \
JOIN_URL="$JOIN_URL" \
REMOTE_BROWSER_ARTIFACT_DIR="$RUN_DIR" \
node "$REPO_ROOT/scripts/remote-control-prod-reliability-browser.cjs" >"$BROWSER_LOG" 2>&1

cleanup
trap - EXIT

RELAY_E2E_NO_GAP_DETECTED="$NO_GAP_DETECTED" \
python3 - "$HARNESS_LOG" "$BROWSER_LOG" "$SUMMARY_PATH" <<'PY'
import json
import os
import pathlib
import sys

harness_path = pathlib.Path(sys.argv[1])
browser_path = pathlib.Path(sys.argv[2])
summary_path = pathlib.Path(sys.argv[3])
require_no_gap_detected = os.environ.get("RELAY_E2E_NO_GAP_DETECTED", "1") == "1"

def load_jsonl(path: pathlib.Path):
    entries = []
    for raw_line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            entries.append({"kind": "non_json_line", "raw": line})
    return entries

harness_entries = load_jsonl(harness_path)
browser_entries = load_jsonl(browser_path)

browser_success = any(entry.get("kind") == "browser_success" for entry in browser_entries)
gap_detected_count = sum(
    1
    for entry in browser_entries
    if entry.get("kind") == "ws_tx" and '"reason":"gap_detected"' in str(entry.get("payload", ""))
)
auth_ok_count = sum(
    1
    for entry in browser_entries
    if entry.get("kind") == "ws_rx" and '"type":"auth_ok"' in str(entry.get("payload", ""))
)
command_received = [
    entry for entry in harness_entries if entry.get("kind") == "command_received"
]
device_list_errors = [
    entry for entry in harness_entries if entry.get("kind") == "devices_list_error"
]
screenshots = [
    entry.get("file")
    for entry in browser_entries
    if entry.get("kind") == "screenshot" and isinstance(entry.get("file"), str)
]

status = "ok"
checks = []

def add_check(name: str, ok: bool, detail: str):
    global status
    checks.append({"name": name, "ok": ok, "detail": detail})
    if not ok:
        status = "failed"

add_check("browser_success", browser_success, f"browser_success={browser_success}")
add_check("auth_ok_count", auth_ok_count >= 2, f"auth_ok_count={auth_ok_count}")
add_check("desktop_commands_received", len(command_received) >= 4, f"commands_received={len(command_received)}")
if require_no_gap_detected:
    add_check("gap_detected_count", gap_detected_count == 0, f"gap_detected_count={gap_detected_count}")

summary = {
    "status": status,
    "joinURLPresent": any(entry.get("kind") == "session_started" for entry in harness_entries),
    "browserSuccess": browser_success,
    "authOKCount": auth_ok_count,
    "gapDetectedCount": gap_detected_count,
    "desktopCommandsReceived": len(command_received),
    "deviceListErrors": len(device_list_errors),
    "screenshots": screenshots,
    "checks": checks,
}

summary_path.parent.mkdir(parents=True, exist_ok=True)
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

if status != "ok":
    raise SystemExit(1)
PY

echo "[remote-control-prod-reliability] PASS"
echo "[remote-control-prod-reliability] artifacts: $RUN_DIR"
echo "[remote-control-prod-reliability] summary: $SUMMARY_PATH"
