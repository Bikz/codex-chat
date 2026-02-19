#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "missing required command: $1"
  fi
}

install_brew_tool_if_missing() {
  local tool="$1"
  if brew list "$tool" >/dev/null 2>&1; then
    echo "Found $tool"
    return 0
  fi

  echo "Installing $tool..."
  brew install "$tool"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  fail "bootstrap.sh supports macOS only"
fi

require_command xcodebuild
require_command swift
require_command git
require_command brew
require_command corepack

echo "Enabling Corepack..."
corepack enable

if ! command -v pnpm >/dev/null 2>&1; then
  echo "Activating pnpm via Corepack..."
  corepack prepare pnpm@10.28.2 --activate
fi

install_brew_tool_if_missing swiftformat
install_brew_tool_if_missing swiftlint
install_brew_tool_if_missing gitleaks

echo "Installing workspace dependencies..."
(cd "$ROOT" && pnpm install)

echo "Running fast validation..."
(cd "$ROOT" && make quick)

cat <<'OUT'

Bootstrap complete.

Next steps:
1. Open host app (canonical GUI path):
   open apps/CodexChatHost/CodexChatHost.xcodeproj
2. Run contributor smoke checks:
   make oss-smoke
3. Run full checks before opening a PR:
   pnpm -s run check
OUT
