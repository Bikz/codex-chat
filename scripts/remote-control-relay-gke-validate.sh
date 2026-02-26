#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KUSTOMIZE_DIR="${RELAY_GKE_KUSTOMIZE_DIR:-$REPO_ROOT/infra/remote-control-relay/gke}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "error: kubectl is required for GKE manifest validation" >&2
  exit 1
fi

if [[ ! -f "$KUSTOMIZE_DIR/kustomization.yaml" ]]; then
  echo "error: missing kustomization at $KUSTOMIZE_DIR" >&2
  exit 1
fi

SECRET_TEMPLATE_PATH="$KUSTOMIZE_DIR/secret-template.yaml"
if [[ ! -f "$SECRET_TEMPLATE_PATH" ]]; then
  SECRET_TEMPLATE_PATH="$REPO_ROOT/infra/remote-control-relay/gke/secret-template.yaml"
fi

if [[ ! -f "$SECRET_TEMPLATE_PATH" ]]; then
  echo "error: missing secret template at $REPO_ROOT/infra/remote-control-relay/gke/secret-template.yaml" >&2
  exit 1
fi

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT

kubectl kustomize "$KUSTOMIZE_DIR" >"$rendered"

required_kinds=(
  "Namespace"
  "ServiceAccount"
  "ConfigMap"
  "Deployment"
  "Service"
  "HorizontalPodAutoscaler"
  "PodDisruptionBudget"
)

for kind in "${required_kinds[@]}"; do
  if ! grep -Eq "^kind: ${kind}$" "$rendered"; then
    echo "error: rendered manifests missing required kind '${kind}'" >&2
    exit 1
  fi
done

echo "[remote-control-gke-validate] note: secret-template.yaml is intentionally excluded from kustomize apply ($SECRET_TEMPLATE_PATH)"

if kubectl cluster-info >/dev/null 2>&1; then
  kubectl apply --dry-run=client --validate=false -f "$rendered" >/dev/null
else
  echo "warning: kubectl is not connected to a cluster; skipping API discovery validation" >&2
fi

echo "[remote-control-gke-validate] PASS"
