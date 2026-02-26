#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${1:-}"
POLICY_NAME="${2:-remote-control-relay-cloud-armor}"
PAIR_LIMIT_PER_MINUTE="${PAIR_LIMIT_PER_MINUTE:-120}"
WS_LIMIT_PER_MINUTE="${WS_LIMIT_PER_MINUTE:-600}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "Usage: $0 <gcp-project-id> [policy-name]" >&2
  exit 1
fi

gcloud config set project "${PROJECT_ID}" >/dev/null

upsert_rule() {
  local priority="$1"
  local expression="$2"
  local threshold="$3"

  if gcloud compute security-policies rules describe "${priority}" \
    --security-policy "${POLICY_NAME}" \
    --project "${PROJECT_ID}" >/dev/null 2>&1; then
    gcloud compute security-policies rules update "${priority}" \
      --security-policy "${POLICY_NAME}" \
      --project "${PROJECT_ID}" \
      --expression="${expression}" \
      --action=throttle \
      --rate-limit-threshold-count="${threshold}" \
      --rate-limit-threshold-interval-sec=60 \
      --conform-action=allow \
      --exceed-action=deny-429 \
      --enforce-on-key=IP >/dev/null
  else
    gcloud compute security-policies rules create "${priority}" \
      --security-policy "${POLICY_NAME}" \
      --project "${PROJECT_ID}" \
      --expression="${expression}" \
      --action=throttle \
      --rate-limit-threshold-count="${threshold}" \
      --rate-limit-threshold-interval-sec=60 \
      --conform-action=allow \
      --exceed-action=deny-429 \
      --enforce-on-key=IP >/dev/null
  fi
}

upsert_rule 1000 "request.path.startsWith('/pair')" "${PAIR_LIMIT_PER_MINUTE}"
upsert_rule 1010 "request.path.startsWith('/ws')" "${WS_LIMIT_PER_MINUTE}"

gcloud compute security-policies describe "${POLICY_NAME}" \
  --project "${PROJECT_ID}" \
  --format='yaml(name,rules)'
