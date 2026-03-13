#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${RELAY_MONITOR_NAMESPACE:-codexchat-remote-control}"
DEPLOYMENT="${RELAY_MONITOR_DEPLOYMENT:-remote-control-relay}"
LABEL_SELECTOR="${RELAY_MONITOR_LABEL_SELECTOR:-app.kubernetes.io/name=remote-control-relay}"
HEALTH_URL="${RELAY_MONITOR_HEALTH_URL:-https://remote.bikz.cc/healthz}"
METRICS_URL="${RELAY_MONITOR_METRICS_URL:-https://remote.bikz.cc/metricsz}"
DURATION_SECONDS="${RELAY_MONITOR_DURATION_SECONDS:-900}"
INTERVAL_SECONDS="${RELAY_MONITOR_INTERVAL_SECONDS:-30}"
SUMMARY_PATH="${RELAY_MONITOR_SUMMARY_PATH:-$(pwd)/output/remote-control/post-deploy-monitor-summary.json}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command missing: $1" >&2
    exit 1
  fi
}

require_command kubectl
require_command curl
require_command python3

mkdir -p "$(dirname "$SUMMARY_PATH")"

end_time=$(( $(date +%s) + DURATION_SECONDS ))
iteration=0

tmp_metrics="$(mktemp)"
tmp_logs="$(mktemp)"
trap 'rm -f "$tmp_metrics" "$tmp_logs"' EXIT

echo "[]" >"$tmp_metrics"
echo "[]" >"$tmp_logs"

last_since_seconds="$INTERVAL_SECONDS"

while (( $(date +%s) < end_time )); do
  iteration=$((iteration + 1))
  now_iso="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  metrics_payload="$(curl -fsS "$METRICS_URL")"
  health_payload="$(curl -fsS "$HEALTH_URL")"
  pod_names="$(kubectl -n "$NAMESPACE" get pods -l "$LABEL_SELECTOR" -o jsonpath='{.items[*].metadata.name}')"

  combined_logs=""
  for pod in $pod_names; do
    pod_logs="$(kubectl -n "$NAMESPACE" logs "$pod" --since="${last_since_seconds}s" 2>/dev/null || true)"
    if [[ -n "$pod_logs" ]]; then
      combined_logs+="$pod_logs"$'\n'
    fi
  done

  python3 - "$tmp_metrics" "$tmp_logs" "$now_iso" "$metrics_payload" "$health_payload" "$combined_logs" <<'PY'
import json
import pathlib
import re
import sys

metrics_path = pathlib.Path(sys.argv[1])
logs_path = pathlib.Path(sys.argv[2])
timestamp = sys.argv[3]
metrics = json.loads(sys.argv[4])
health = json.loads(sys.argv[5])
combined_logs = sys.argv[6]

metric_entries = json.loads(metrics_path.read_text(encoding="utf-8"))
metric_entries.append({
    "timestamp": timestamp,
    "metrics": metrics,
    "health": health,
})
metrics_path.write_text(json.dumps(metric_entries, indent=2) + "\n", encoding="utf-8")

reason_pattern = re.compile(r"ws_auth_failure reason=([a-zA-Z0-9_]+)")
log_entries = json.loads(logs_path.read_text(encoding="utf-8"))
reason_counts = {}
for reason in reason_pattern.findall(combined_logs):
    reason_counts[reason] = reason_counts.get(reason, 0) + 1
log_entries.append({
    "timestamp": timestamp,
    "wsAuthFailureReasons": reason_counts,
})
logs_path.write_text(json.dumps(log_entries, indent=2) + "\n", encoding="utf-8")
PY

  echo "[remote-control-post-deploy-monitor] sample ${iteration} at ${now_iso}"
  last_since_seconds="$INTERVAL_SECONDS"
  sleep "$INTERVAL_SECONDS"
done

python3 - "$tmp_metrics" "$tmp_logs" "$SUMMARY_PATH" <<'PY'
import json
import pathlib
import sys

metrics_entries = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
log_entries = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
summary_path = pathlib.Path(sys.argv[3])

latest_metrics = metrics_entries[-1]["metrics"] if metrics_entries else {}
health_failures = [
    entry["timestamp"]
    for entry in metrics_entries
    if not entry.get("health", {}).get("ok", False)
]
ws_auth_failure_delta = 0
outbound_send_failure_delta = 0
slow_consumer_disconnect_delta = 0
if len(metrics_entries) >= 2:
    first = metrics_entries[0]["metrics"]
    last = metrics_entries[-1]["metrics"]
    ws_auth_failure_delta = int(last.get("wsAuthFailures", 0)) - int(first.get("wsAuthFailures", 0))
    outbound_send_failure_delta = int(last.get("outboundSendFailures", 0)) - int(first.get("outboundSendFailures", 0))
    slow_consumer_disconnect_delta = int(last.get("slowConsumerDisconnects", 0)) - int(first.get("slowConsumerDisconnects", 0))

reason_totals = {}
for entry in log_entries:
    for reason, count in entry.get("wsAuthFailureReasons", {}).items():
        reason_totals[reason] = reason_totals.get(reason, 0) + int(count)

summary = {
    "status": "ok" if not health_failures else "failed",
    "samples": len(metrics_entries),
    "latestMetrics": latest_metrics,
    "wsAuthFailureDelta": ws_auth_failure_delta,
    "outboundSendFailureDelta": outbound_send_failure_delta,
    "slowConsumerDisconnectDelta": slow_consumer_disconnect_delta,
    "wsAuthFailureReasons": reason_totals,
    "healthFailures": health_failures,
}

summary_path.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")
print(json.dumps(summary, indent=2))

if health_failures:
    raise SystemExit(1)
PY
