#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELAY_NODE_DIR="$REPO_ROOT/apps/RemoteControlRelay"

cd "$RELAY_NODE_DIR"
pnpm -s exec node --test test/relay.compat.test.mjs
