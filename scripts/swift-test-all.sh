#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for dir in "$ROOT"/apps/CodexChatApp "$ROOT"/packages/*; do
  if [[ -f "$dir/Package.swift" ]]; then
    echo "Testing $(basename "$dir")"
    (cd "$dir" && swift test)
  fi
done
