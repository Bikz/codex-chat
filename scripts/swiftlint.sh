#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v swiftlint >/dev/null 2>&1; then
  echo "swiftlint is required. Install with: brew install swiftlint" >&2
  exit 1
fi

swiftlint lint --config "$ROOT/.swiftlint.yml"

