#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REMOTE="${1:-origin}"

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [remote]" >&2
  exit 1
fi

next_version="$("$ROOT/scripts/release/next-version.sh" "v")"

if git rev-parse -q --verify "refs/tags/$next_version" >/dev/null; then
  echo "error: tag already exists: $next_version" >&2
  exit 1
fi

git tag "$next_version"
git push "$REMOTE" "$next_version"

echo "Created and pushed tag: $next_version"
