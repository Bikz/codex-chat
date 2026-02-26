#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

LOAD_RESULT_PATH="${RELAY_STAGE_GATE_LOAD_RESULT_PATH:-$REPO_ROOT/output/remote-control/relay-load-result.json}"
SOAK_SUMMARY_PATH="${RELAY_STAGE_GATE_SOAK_SUMMARY_PATH:-$REPO_ROOT/output/remote-control/relay-soak-summary.json}"
REPORT_PATH="${RELAY_STAGE_GATE_REPORT_PATH:-$REPO_ROOT/output/remote-control/stage-gate-report.md}"

if [[ ! -f "$LOAD_RESULT_PATH" ]]; then
  echo "error: missing load result artifact at $LOAD_RESULT_PATH" >&2
  exit 1
fi

if [[ ! -f "$SOAK_SUMMARY_PATH" ]]; then
  echo "error: missing soak summary artifact at $SOAK_SUMMARY_PATH" >&2
  exit 1
fi

if ! "$REPO_ROOT/scripts/remote-control-relay-gke-validate.sh" >/tmp/remote-control-gke-validate.log 2>&1; then
  echo "error: gke manifest validation failed" >&2
  cat /tmp/remote-control-gke-validate.log >&2
  exit 1
fi

python3 - "$LOAD_RESULT_PATH" "$SOAK_SUMMARY_PATH" "$REPORT_PATH" <<'PY'
import json
import pathlib
import sys
from datetime import datetime, timezone

load_path = pathlib.Path(sys.argv[1])
soak_path = pathlib.Path(sys.argv[2])
report_path = pathlib.Path(sys.argv[3])

load = json.loads(load_path.read_text(encoding="utf-8"))
soak = json.loads(soak_path.read_text(encoding="utf-8"))

checks = [
    ("Load status", load.get("status") == "ok", f"status={load.get('status')}"),
    ("Load latency budget", bool(load.get("passes_latency_budget")), f"p95_ms={load.get('p95_latency_ms')} budget_ms={load.get('p95_latency_budget_ms')}"),
    ("Load backpressure budget", bool(load.get("passes_backpressure_budget")), f"outbound_send_failures={load.get('outbound_send_failures')} slow_consumer_disconnects={load.get('slow_consumer_disconnects')}"),
    ("Load auth budget", bool(load.get("passes_auth_budget", True)), f"ws_auth_failures={load.get('ws_auth_failures', 0)}"),
    ("Soak status", soak.get("status") == "ok", f"status={soak.get('status')}"),
    ("Soak failing loops", int(soak.get("failing_loops", 1)) == 0, f"failing_loops={soak.get('failing_loops')}"),
    ("Soak total errors", int(soak.get("total_errors", 1)) == 0, f"total_errors={soak.get('total_errors')}"),
]

passed = [entry for entry in checks if entry[1]]
failed = [entry for entry in checks if not entry[1]]
overall_ok = len(failed) == 0

lines = []
lines.append("# Remote Control Stage Gate Report")
lines.append("")
lines.append(f"- Generated at: {datetime.now(timezone.utc).isoformat()}")
lines.append(f"- Load artifact: `{load_path}`")
lines.append(f"- Soak artifact: `{soak_path}`")
lines.append(f"- Overall: {'PASS' if overall_ok else 'FAIL'}")
lines.append("")
lines.append("## Checks")
lines.append("")
for name, ok, detail in checks:
    icon = "PASS" if ok else "FAIL"
    lines.append(f"- {icon}: {name} ({detail})")
lines.append("")
lines.append("## Summary")
lines.append("")
lines.append(f"- Passed: {len(passed)}")
lines.append(f"- Failed: {len(failed)}")

report_path.parent.mkdir(parents=True, exist_ok=True)
report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

if not overall_ok:
    sys.exit(1)
PY

echo "[remote-control-stage-gate] PASS"
echo "[remote-control-stage-gate] report: $REPORT_PATH"
