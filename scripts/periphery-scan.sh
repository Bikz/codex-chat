#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v periphery >/dev/null 2>&1; then
  echo "periphery is required. Install with: brew install periphery" >&2
  exit 1
fi

cd "$ROOT/apps/CodexChatApp"

# Optional dead-code scan (non-blocking in CI). This is intentionally not strict yet.
periphery scan \
  --relative-results \
  --format xcode \
  --retain-public \
  --retain-codable-properties \
  --retain-swift-ui-previews

