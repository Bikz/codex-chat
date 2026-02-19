#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_cli_smoke() {
  echo "Running CodexChatCLI doctor/smoke/repro..."
  (
    cd "$ROOT/apps/CodexChatApp"
    swift run CodexChatCLI doctor
    swift run CodexChatCLI smoke
    swift run CodexChatCLI repro --fixture basic-turn
  )
}

run_host_build() {
  echo "Building canonical host app (unsigned)..."
  local derived_data
  local status
  derived_data="$(mktemp -d "${TMPDIR:-/tmp}/codexchat-oss-smoke-deriveddata.XXXXXX")"
  set +e
  xcodebuild \
    -quiet \
    -project "$ROOT/apps/CodexChatHost/CodexChatHost.xcodeproj" \
    -scheme CodexChatHost \
    -configuration Debug \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build
  status=$?
  set -e
  rm -rf "$derived_data"
  return $status
}

run_cli_smoke
run_host_build

echo "OSS smoke checks passed"
