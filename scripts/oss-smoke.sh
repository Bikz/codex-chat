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

run_remote_control_compat() {
  if [[ "${OSS_SMOKE_SKIP_REMOTE_CONTROL_COMPAT:-0}" == "1" ]]; then
    echo "Skipping remote-control relay compatibility smoke (OSS_SMOKE_SKIP_REMOTE_CONTROL_COMPAT=1)"
    return
  fi

  echo "Running remote-control relay compatibility smoke..."
  "$ROOT/scripts/remote-control-relay-compat.sh"
}

run_cli_smoke
run_remote_control_compat
run_host_build

echo "OSS smoke checks passed"
