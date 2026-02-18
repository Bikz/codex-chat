#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftformat >/dev/null 2>&1; then
  echo "swiftformat is required. Install with: brew install swiftformat" >&2
  exit 1
fi

swiftformat --lint --config "$ROOT/.swiftformat" "$ROOT"

