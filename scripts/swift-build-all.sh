#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT/scripts/check-host-app-metadata.sh"
"$ROOT/scripts/verify-build-settings-parity.sh"

echo "Building CodexChatHost (canonical GUI app)"
xcodebuild \
  -quiet \
  -project "$ROOT/apps/CodexChatHost/CodexChatHost.xcodeproj" \
  -scheme CodexChatHost \
  -configuration Debug \
  -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

for dir in "$ROOT"/apps/CodexChatApp "$ROOT"/packages/*; do
  if [[ -f "$dir/Package.swift" ]]; then
    echo "Building $(basename "$dir")"
    (cd "$dir" && swift build)
  fi
done
