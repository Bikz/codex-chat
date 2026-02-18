#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Tight-loop test subset (keep this sub-minute on a typical dev machine).
DIRS=(
  "$ROOT/packages/CodexKit"
  "$ROOT/packages/CodexChatCore"
  "$ROOT/packages/CodexChatInfra"
)

for dir in "${DIRS[@]}"; do
  echo "Testing $(basename "$dir")"
  (cd "$dir" && swift test)
done

