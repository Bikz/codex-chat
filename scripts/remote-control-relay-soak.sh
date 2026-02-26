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

if [[ ! "$SOAK_LOOPS" =~ ^[1-9][0-9]*$ ]]; then
  echo "error: RELAY_SOAK_LOOPS must be a positive integer (got '$SOAK_LOOPS')" >&2
  exit 1
fi

echo "[remote-control-soak] starting ${SOAK_LOOPS} harness loops"

for ((i = 1; i <= SOAK_LOOPS; i++)); do
  echo "[remote-control-soak] loop ${i}/${SOAK_LOOPS}"
  "$LOAD_SCRIPT"
done

echo "[remote-control-soak] completed ${SOAK_LOOPS} loops"
