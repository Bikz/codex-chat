#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

RESULTS_PATH="${RELAY_GATE_RESULTS_PATH:-$REPO_ROOT/output/remote-control/relay-load-result.json}"

if [[ ! -f "$RESULTS_PATH" ]]; then
  echo "error: relay load results artifact not found at $RESULTS_PATH" >&2
  echo "hint: run scripts/remote-control-relay-load.sh first or set RELAY_GATE_RESULTS_PATH" >&2
  exit 1
fi

python3 - "$RESULTS_PATH" <<'PY'
import json
import os
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    payload = json.load(handle)

status = str(payload.get("status", ""))
sample_count = int(payload.get("sample_count", 0) or 0)
p95_latency_us = int(payload.get("p95_latency_us", 0) or 0)
p95_latency_ms = int(payload.get("p95_latency_ms", 0) or 0)
p95_budget_ms = int(payload.get("p95_latency_budget_ms", 0) or 0)
error_count = int(payload.get("error_count", 0) or 0)
outbound_send_failures = int(payload.get("outbound_send_failures", 0) or 0)
slow_consumer_disconnects = int(payload.get("slow_consumer_disconnects", 0) or 0)
ws_auth_failures = int(payload.get("ws_auth_failures", 0) or 0)
first_error = payload.get("first_error")

required_status = os.getenv("RELAY_GATE_REQUIRE_STATUS", "ok").strip()
max_p95_us_raw = os.getenv("RELAY_GATE_MAX_P95_US", "").strip()
max_p95_raw = os.getenv("RELAY_GATE_MAX_P95_MS", "").strip()
max_errors = int(os.getenv("RELAY_GATE_MAX_ERRORS", "0"))
max_outbound_send_failures = int(os.getenv("RELAY_GATE_MAX_OUTBOUND_SEND_FAILURES", "0"))
max_slow_consumer_disconnects = int(os.getenv("RELAY_GATE_MAX_SLOW_CONSUMER_DISCONNECTS", "0"))
max_ws_auth_failures = int(os.getenv("RELAY_GATE_MAX_WS_AUTH_FAILURES", "0"))
min_sample_count = int(os.getenv("RELAY_GATE_MIN_SAMPLE_COUNT", "1"))

if max_p95_us_raw:
    max_p95_us = int(max_p95_us_raw)
else:
    max_p95_us = None

if max_p95_raw:
    max_p95_ms = int(max_p95_raw)
elif p95_budget_ms > 0:
    max_p95_ms = p95_budget_ms
else:
    max_p95_ms = p95_latency_ms

print("[remote-control-gate] evaluating relay load artifact:")
print(f"  path={path}")
print(f"  status={status}")
print(f"  samples={sample_count}")
print(f"  p95_latency_us={p95_latency_us}")
print(f"  p95_latency_ms={p95_latency_ms}")
if max_p95_us is not None:
    print(f"  p95_gate_us={max_p95_us}")
else:
    print(f"  p95_gate_ms={max_p95_ms}")
print(f"  error_count={error_count}")
print(f"  outbound_send_failures={outbound_send_failures}")
print(f"  slow_consumer_disconnects={slow_consumer_disconnects}")
print(f"  ws_auth_failures={ws_auth_failures}")

failures = []

if required_status and status != required_status:
    failures.append(f"status '{status}' did not match required status '{required_status}'")
if sample_count < min_sample_count:
    failures.append(f"sample_count {sample_count} below minimum {min_sample_count}")
if max_p95_us is not None:
    if p95_latency_us > max_p95_us:
        failures.append(f"p95_latency_us {p95_latency_us} exceeded gate {max_p95_us}")
elif p95_latency_ms > max_p95_ms:
    failures.append(f"p95_latency_ms {p95_latency_ms} exceeded gate {max_p95_ms}")
if error_count > max_errors:
    failures.append(f"error_count {error_count} exceeded gate {max_errors}")
if outbound_send_failures > max_outbound_send_failures:
    failures.append(
        f"outbound_send_failures {outbound_send_failures} exceeded gate {max_outbound_send_failures}"
    )
if slow_consumer_disconnects > max_slow_consumer_disconnects:
    failures.append(
        f"slow_consumer_disconnects {slow_consumer_disconnects} exceeded gate {max_slow_consumer_disconnects}"
    )
if ws_auth_failures > max_ws_auth_failures:
    failures.append(
        f"ws_auth_failures {ws_auth_failures} exceeded gate {max_ws_auth_failures}"
    )

if failures:
    print("[remote-control-gate] FAILED", file=sys.stderr)
    for failure in failures:
        print(f"  - {failure}", file=sys.stderr)
    if first_error:
        print(f"  - first_error: {first_error}", file=sys.stderr)
    sys.exit(1)

print("[remote-control-gate] PASS")
PY
