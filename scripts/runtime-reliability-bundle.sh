#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)-${RANDOM}-$$"
BASE_DIR="${RELIABILITY_BUNDLE_DIR:-$ROOT/.artifacts/reliability/bundles}"
BUNDLE_DIR="$BASE_DIR/reliability-bundle-$STAMP"
ARCHIVE_PATH="$BASE_DIR/reliability-bundle-$STAMP.tgz"

mkdir -p "$BUNDLE_DIR"

if [[ "${RELIABILITY_BUNDLE_SKIP_SCORECARD:-0}" != "1" ]]; then
  echo "==> Generating fresh reliability scorecard"
  make -C "$ROOT" reliability-scorecard
fi

echo "==> Capturing runtime diagnostics"
swift run --package-path "$ROOT/apps/CodexChatApp" CodexChatCLI doctor > "$BUNDLE_DIR/doctor.txt"
swift run --package-path "$ROOT/apps/CodexChatApp" CodexChatCLI smoke > "$BUNDLE_DIR/smoke.txt"
swift run --package-path "$ROOT/apps/CodexChatApp" CodexChatCLI policy validate \
  --file "$ROOT/config/runtime-policy/default-policy.json" > "$BUNDLE_DIR/policy-validate.txt"

LATEST_SCORECARD_STEM="$(
  find "$ROOT/.artifacts/reliability" -maxdepth 1 -type f \( -name 'scorecard-*.md' -o -name 'scorecard-*.json' \) \
    | sed -E 's/\.(md|json)$//' \
    | sort \
    | tail -n 1 || true
)"

if [[ -n "$LATEST_SCORECARD_STEM" ]]; then
  for ext in md json; do
    candidate="${LATEST_SCORECARD_STEM}.${ext}"
    if [[ -f "$candidate" ]]; then
      cp "$candidate" "$BUNDLE_DIR/"
    fi
  done
fi

{
  echo "generated_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_sha=$(git -C "$ROOT" rev-parse HEAD)"
  echo "branch=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)"
  echo "policy_file=config/runtime-policy/default-policy.json"
} > "$BUNDLE_DIR/metadata.env"

tar -czf "$ARCHIVE_PATH" -C "$BASE_DIR" "$(basename "$BUNDLE_DIR")"

echo
echo "Reliability diagnostics bundle created:"
echo "- Directory: $BUNDLE_DIR"
echo "- Archive: $ARCHIVE_PATH"
