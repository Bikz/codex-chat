#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOAD_SCRIPT="$REPO_ROOT/scripts/remote-control-relay-load.sh"

if [[ ! -x "$LOAD_SCRIPT" ]]; then
  echo "error: missing executable load script at $LOAD_SCRIPT" >&2
  exit 1
fi

SOAK_LOOPS="${RELAY_SOAK_LOOPS:-5}"
SOAK_RESULTS_DIR="${RELAY_SOAK_RESULTS_DIR:-$REPO_ROOT/output/remote-control/soak-runs}"
SOAK_SUMMARY_PATH="${RELAY_SOAK_SUMMARY_PATH:-$REPO_ROOT/output/remote-control/relay-soak-summary.json}"

if [[ ! "$SOAK_LOOPS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: RELAY_SOAK_LOOPS must be a positive integer (got '$SOAK_LOOPS')" >&2
  exit 1
fi

mkdir -p "$SOAK_RESULTS_DIR"

load_script_failures=0

echo "[remote-control-soak] starting ${SOAK_LOOPS} harness loops"
echo "[remote-control-soak] results directory: $SOAK_RESULTS_DIR"
echo "[remote-control-soak] summary path: $SOAK_SUMMARY_PATH"

for ((i = 1; i <= SOAK_LOOPS; i++)); do
  loop_result_path="$SOAK_RESULTS_DIR/loop-${i}.json"
  rm -f "$loop_result_path"
  echo "[remote-control-soak] loop ${i}/${SOAK_LOOPS} (artifact: $loop_result_path)"

  set +e
  RELAY_LOAD_RESULTS_PATH="$loop_result_path" "$LOAD_SCRIPT"
  loop_exit_code=$?
  set -e

  if [[ $loop_exit_code -ne 0 ]]; then
    load_script_failures=$((load_script_failures + 1))
    echo "[remote-control-soak] loop ${i} failed with exit code $loop_exit_code"
  fi
done

RELAY_SOAK_LOOPS_EXPECTED="$SOAK_LOOPS" \
RELAY_SOAK_LOAD_SCRIPT_FAILURES="$load_script_failures" \
RELAY_SOAK_RESULTS_DIR="$SOAK_RESULTS_DIR" \
RELAY_SOAK_SUMMARY_PATH="$SOAK_SUMMARY_PATH" \
python3 - <<'PY'
import json
import os
import sys
from pathlib import Path

results_dir = Path(os.environ["RELAY_SOAK_RESULTS_DIR"])
summary_path = Path(os.environ["RELAY_SOAK_SUMMARY_PATH"])
expected_loops = int(os.environ["RELAY_SOAK_LOOPS_EXPECTED"])
load_script_failures = int(os.environ["RELAY_SOAK_LOAD_SCRIPT_FAILURES"])

max_failing_loops = int(os.getenv("RELAY_SOAK_MAX_FAILING_LOOPS", "0"))
max_p95_us_raw = os.getenv("RELAY_SOAK_MAX_P95_US", "").strip()
max_p95_raw = os.getenv("RELAY_SOAK_MAX_P95_MS", "").strip()
max_total_errors = int(os.getenv("RELAY_SOAK_MAX_TOTAL_ERRORS", "0"))
max_total_outbound = int(os.getenv("RELAY_SOAK_MAX_TOTAL_OUTBOUND_SEND_FAILURES", "0"))
max_total_slow = int(os.getenv("RELAY_SOAK_MAX_TOTAL_SLOW_CONSUMER_DISCONNECTS", "0"))
max_total_ws_auth_failures = int(os.getenv("RELAY_SOAK_MAX_TOTAL_WS_AUTH_FAILURES", "0"))
min_total_samples = int(os.getenv("RELAY_SOAK_MIN_TOTAL_SAMPLES", "1"))

loop_payloads = []
missing_artifacts = []

for index in range(1, expected_loops + 1):
    path = results_dir / f"loop-{index}.json"
    if not path.exists():
        missing_artifacts.append(str(path))
        continue
    try:
        loop_payloads.append(json.loads(path.read_text(encoding="utf-8")))
    except Exception as error:
        loop_payloads.append(
            {
                "status": "artifact_decode_error",
                "sample_count": 0,
                "p95_latency_ms": 0,
                "error_count": 1,
                "outbound_send_failures": 0,
                "slow_consumer_disconnects": 0,
                "first_error": f"failed decoding {path.name}: {error}",
            }
        )

ok_loops = 0
status_failures = 0
max_p95_seen = 0
max_p95_us_seen = 0
total_samples = 0
total_errors = 0
total_outbound_send_failures = 0
total_slow_consumer_disconnects = 0
total_ws_auth_failures = 0
first_error = None

for payload in loop_payloads:
    status = str(payload.get("status", ""))
    if status == "ok":
        ok_loops += 1
    else:
        status_failures += 1

    p95 = int(payload.get("p95_latency_ms", 0) or 0)
    p95_us = int(payload.get("p95_latency_us", 0) or 0)
    max_p95_seen = max(max_p95_seen, p95)
    max_p95_us_seen = max(max_p95_us_seen, p95_us)
    total_samples += int(payload.get("sample_count", 0) or 0)
    total_errors += int(payload.get("error_count", 0) or 0)
    total_outbound_send_failures += int(payload.get("outbound_send_failures", 0) or 0)
    total_slow_consumer_disconnects += int(payload.get("slow_consumer_disconnects", 0) or 0)
    total_ws_auth_failures += int(payload.get("ws_auth_failures", 0) or 0)
    if first_error is None and payload.get("first_error"):
        first_error = str(payload["first_error"])

failing_loops = status_failures + len(missing_artifacts) + load_script_failures
max_p95_us_gate = int(max_p95_us_raw) if max_p95_us_raw else None
max_p95_gate = int(max_p95_raw) if max_p95_raw else None

gate_failures = []
if failing_loops > max_failing_loops:
    gate_failures.append(f"failing_loops {failing_loops} exceeded gate {max_failing_loops}")
if max_p95_us_gate is not None and max_p95_us_seen > max_p95_us_gate:
    gate_failures.append(f"max_p95_us {max_p95_us_seen} exceeded gate {max_p95_us_gate}")
elif max_p95_gate is not None and max_p95_seen > max_p95_gate:
    gate_failures.append(f"max_p95_ms {max_p95_seen} exceeded gate {max_p95_gate}")
if total_errors > max_total_errors:
    gate_failures.append(f"total_errors {total_errors} exceeded gate {max_total_errors}")
if total_outbound_send_failures > max_total_outbound:
    gate_failures.append(
        f"total_outbound_send_failures {total_outbound_send_failures} exceeded gate {max_total_outbound}"
    )
if total_slow_consumer_disconnects > max_total_slow:
    gate_failures.append(
        f"total_slow_consumer_disconnects {total_slow_consumer_disconnects} exceeded gate {max_total_slow}"
    )
if total_ws_auth_failures > max_total_ws_auth_failures:
    gate_failures.append(
        f"total_ws_auth_failures {total_ws_auth_failures} exceeded gate {max_total_ws_auth_failures}"
    )
if total_samples < min_total_samples:
    gate_failures.append(f"total_samples {total_samples} below minimum {min_total_samples}")

summary = {
    "status": "ok" if not gate_failures else "failed",
    "expected_loops": expected_loops,
    "artifact_loops": len(loop_payloads),
    "ok_loops": ok_loops,
    "status_failures": status_failures,
    "missing_artifacts": missing_artifacts,
    "load_script_failures": load_script_failures,
    "failing_loops": failing_loops,
    "total_samples": total_samples,
    "max_p95_latency_us": max_p95_us_seen,
    "max_p95_latency_ms": max_p95_seen,
    "total_errors": total_errors,
    "total_outbound_send_failures": total_outbound_send_failures,
    "total_slow_consumer_disconnects": total_slow_consumer_disconnects,
    "total_ws_auth_failures": total_ws_auth_failures,
    "first_error": first_error,
    "gate": {
        "max_failing_loops": max_failing_loops,
        "max_p95_us": max_p95_us_gate,
        "max_p95_ms": max_p95_gate,
        "max_total_errors": max_total_errors,
        "max_total_outbound_send_failures": max_total_outbound,
        "max_total_slow_consumer_disconnects": max_total_slow,
        "max_total_ws_auth_failures": max_total_ws_auth_failures,
        "min_total_samples": min_total_samples,
    },
    "gate_failures": gate_failures,
}

summary_path.parent.mkdir(parents=True, exist_ok=True)
summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")

print("[remote-control-soak] summary:")
print(f"  path={summary_path}")
print(f"  status={summary['status']}")
print(f"  expected_loops={expected_loops} artifact_loops={len(loop_payloads)} ok_loops={ok_loops}")
print(f"  failing_loops={failing_loops}")
print(f"  total_samples={total_samples}")
print(f"  max_p95_latency_us={max_p95_us_seen}")
print(f"  max_p95_latency_ms={max_p95_seen}")
print(f"  total_errors={total_errors}")
print(f"  total_outbound_send_failures={total_outbound_send_failures}")
print(f"  total_slow_consumer_disconnects={total_slow_consumer_disconnects}")
print(f"  total_ws_auth_failures={total_ws_auth_failures}")

if gate_failures:
    print("[remote-control-soak] FAILED", file=sys.stderr)
    for failure in gate_failures:
        print(f"  - {failure}", file=sys.stderr)
    if first_error:
        print(f"  - first_error: {first_error}", file=sys.stderr)
    sys.exit(1)

print("[remote-control-soak] PASS")
PY
