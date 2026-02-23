#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELIABILITY_ENABLE_SOAK="${RELIABILITY_ENABLE_SOAK:-0}"
RELIABILITY_SOAK_LOOPS="${RELIABILITY_SOAK_LOOPS:-3}"

run_suite() {
  local package_path="$1"
  local filter="$2"
  local label="$3"

  echo
  echo "==> ${label}"
  (
    cd "$ROOT/$package_path"
    swift test --filter "$filter"
  )
}

SECONDS=0

echo "Running Team A local reliability harness"
echo "Repository: $ROOT"

run_suite \
  "packages/CodexKit" \
  "CodexRuntimeIntegrationTests" \
  "CodexKit runtime protocol and handshake invariants"

run_suite \
  "packages/CodexChatInfra" \
  "SQLiteFollowUpQueueFairnessTests" \
  "Infra follow-up queue fairness invariants"

run_suite \
  "apps/CodexChatApp" \
  "RuntimeAutoRecoveryTests|RuntimeStaleThreadRecoveryPolicyTests|RuntimeApprovalContinuityTests|ChatArchiveStoreCheckpointTests|PersistenceBatcherTests" \
  "App runtime recovery and durability invariants"

if [[ "$RELIABILITY_ENABLE_SOAK" == "1" ]]; then
  if [[ ! "$RELIABILITY_SOAK_LOOPS" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: RELIABILITY_SOAK_LOOPS must be a positive integer" >&2
    exit 1
  fi

  for ((i = 1; i <= RELIABILITY_SOAK_LOOPS; i++)); do
    run_suite \
      "apps/CodexChatApp" \
      "RuntimePoolResilienceTests" \
      "RuntimePool resilience soak (${i}/${RELIABILITY_SOAK_LOOPS})"
  done
fi

echo
echo "Team A reliability harness passed in ${SECONDS}s"
