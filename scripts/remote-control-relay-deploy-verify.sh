#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="${RELAY_DEPLOY_NAMESPACE:-codexchat-remote-control}"
DEPLOYMENT="${RELAY_DEPLOYMENT_NAME:-remote-control-relay}"
LABEL_SELECTOR="${RELAY_DEPLOY_LABEL_SELECTOR:-app.kubernetes.io/name=remote-control-relay}"
HEALTH_URL="${RELAY_HEALTH_URL:-https://remote.bikz.cc/healthz}"
EXPECTED_IMAGE="${RELAY_EXPECTED_IMAGE:-}"
EXPECTED_DIGEST="${RELAY_EXPECTED_DIGEST:-}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command missing: $1" >&2
    exit 1
  fi
}

require_command kubectl
require_command curl
require_command python3

kubectl -n "$NAMESPACE" rollout status "deploy/$DEPLOYMENT" --timeout=180s >/dev/null

deployment_info="$(kubectl -n "$NAMESPACE" get deploy "$DEPLOYMENT" -o json)"
pod_info="$(kubectl -n "$NAMESPACE" get pods -l "$LABEL_SELECTOR" -o json)"
health_payload="$(curl -fsS "$HEALTH_URL")"

VERIFY_EXPECTED_IMAGE="$EXPECTED_IMAGE" \
VERIFY_EXPECTED_DIGEST="$EXPECTED_DIGEST" \
python3 - "$deployment_info" "$pod_info" "$health_payload" <<'PY'
import json
import os
import sys

deployment = json.loads(sys.argv[1])
pods = json.loads(sys.argv[2])
health = json.loads(sys.argv[3])
expected_image = os.environ.get("VERIFY_EXPECTED_IMAGE", "").strip()
expected_digest = os.environ.get("VERIFY_EXPECTED_DIGEST", "").strip()

spec = deployment["spec"]
status = deployment["status"]
deployment_image = spec["template"]["spec"]["containers"][0]["image"]

pod_rows = []
for item in pods.get("items", []):
    container = item["spec"]["containers"][0]
    status_row = (item.get("status", {}).get("containerStatuses") or [{}])[0]
    pod_rows.append(
        {
            "name": item["metadata"]["name"],
            "image": container["image"],
            "imageID": status_row.get("imageID"),
            "ready": bool(status_row.get("ready")),
            "restartCount": int(status_row.get("restartCount", 0)),
        }
    )

errors = []
if status.get("observedGeneration") != deployment["metadata"].get("generation"):
    errors.append("deployment generation is not fully observed")
if int(status.get("updatedReplicas", 0)) != int(spec.get("replicas", 0)):
    errors.append("not all replicas are updated")
if int(status.get("readyReplicas", 0)) != int(spec.get("replicas", 0)):
    errors.append("not all replicas are ready")
if int(status.get("availableReplicas", 0)) != int(spec.get("replicas", 0)):
    errors.append("not all replicas are available")
if not health.get("ok"):
    errors.append("healthz returned ok=false")

if expected_image and deployment_image != expected_image:
    errors.append(f"deployment image mismatch: {deployment_image} != {expected_image}")
if expected_digest and expected_digest not in deployment_image:
    errors.append(f"deployment digest mismatch: {deployment_image} does not include {expected_digest}")

if len(pod_rows) != int(spec.get("replicas", 0)):
    errors.append(f"expected {spec.get('replicas', 0)} pods, found {len(pod_rows)}")

for pod in pod_rows:
    if not pod["ready"]:
        errors.append(f"pod not ready: {pod['name']}")
    if pod["restartCount"] != 0:
        errors.append(f"pod restarted unexpectedly: {pod['name']} restartCount={pod['restartCount']}")
    if pod["image"] != deployment_image:
        errors.append(f"pod image mismatch: {pod['name']} image={pod['image']}")
    if expected_digest and expected_digest not in (pod["imageID"] or ""):
        errors.append(f"pod imageID mismatch: {pod['name']} imageID={pod['imageID']}")

summary = {
    "deployment": deployment["metadata"]["name"],
    "namespace": deployment["metadata"]["namespace"],
    "deploymentImage": deployment_image,
    "replicas": {
        "spec": spec.get("replicas"),
        "updated": status.get("updatedReplicas"),
        "ready": status.get("readyReplicas"),
        "available": status.get("availableReplicas"),
    },
    "healthz": health,
    "pods": pod_rows,
    "status": "ok" if not errors else "failed",
    "errors": errors,
}

print(json.dumps(summary, indent=2))

if errors:
    raise SystemExit(1)
PY
