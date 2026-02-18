#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Knip is only useful when JS/TS sources exist. Skip for Swift-only workspaces.
HAS_SOURCES="$(
  find . \
    \( \
      -path "./node_modules" -o \
      -path "./docs" -o \
      -path "./DerivedData" -o \
      -path "*/.build/*" -o \
      -path "*/.swiftpm/*" \
    \) -prune -o \
    -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.cjs" \) \
    -print -quit
)"

if [[ -z "${HAS_SOURCES}" ]]; then
  echo "knip: no JS/TS sources detected; skipping."
  exit 0
fi

pnpm exec knip

