#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${RELIABILITY_SCORECARD_DIR:-$ROOT/.artifacts/reliability}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
JSON_PATH="$OUT_DIR/scorecard-$STAMP.json"
MD_PATH="$OUT_DIR/scorecard-$STAMP.md"
TMP_RESULTS="$(mktemp)"

mkdir -p "$OUT_DIR"

run_check() {
  local name="$1"
  shift

  local started
  started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local start_epoch
  start_epoch="$(date +%s)"

  echo
  echo "==> $name"

  local status="pass"
  if ! "$@"; then
    status="fail"
  fi

  local end_epoch
  end_epoch="$(date +%s)"
  local duration=$((end_epoch - start_epoch))
  local finished
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$status" "$duration" "$started" "$finished" >> "$TMP_RESULTS"
}

TOTAL_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TOTAL_START_EPOCH="$(date +%s)"

run_check "local reliability harness" make -C "$ROOT" reliability-local
run_check "targeted smoke" make -C "$ROOT" oss-smoke
run_check "repro fixture: basic-turn" \
  swift run --package-path "$ROOT/apps/CodexChatApp" CodexChatCLI repro --fixture basic-turn
run_check "repro fixture: runtime-termination-recovery" \
  swift run --package-path "$ROOT/apps/CodexChatApp" CodexChatCLI repro --fixture runtime-termination-recovery
run_check "repro fixture: stale-thread-remap" \
  swift run --package-path "$ROOT/apps/CodexChatApp" CodexChatCLI repro --fixture stale-thread-remap

TOTAL_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TOTAL_END_EPOCH="$(date +%s)"
TOTAL_DURATION=$((TOTAL_END_EPOCH - TOTAL_START_EPOCH))
GIT_SHA="$(git -C "$ROOT" rev-parse --short HEAD)"

HAS_FAILURE=0
while IFS=$'\t' read -r _name status _duration _started _finished; do
  if [[ "$status" != "pass" ]]; then
    HAS_FAILURE=1
    break
  fi
done < "$TMP_RESULTS"

{
  echo "{"
  echo "  \"generatedAt\": \"$TOTAL_END\"," 
  echo "  \"gitSha\": \"$GIT_SHA\"," 
  echo "  \"totalDurationSeconds\": $TOTAL_DURATION,"
  echo "  \"overallStatus\": \"$([[ $HAS_FAILURE -eq 0 ]] && echo pass || echo fail)\"," 
  echo "  \"checks\": ["

  first=1
  while IFS=$'\t' read -r name status duration started finished; do
    if [[ $first -eq 0 ]]; then
      echo "    ,"
    fi
    first=0
    echo "    {"
    echo "      \"name\": \"$name\"," 
    echo "      \"status\": \"$status\"," 
    echo "      \"durationSeconds\": $duration,"
    echo "      \"startedAt\": \"$started\"," 
    echo "      \"finishedAt\": \"$finished\""
    echo "    }"
  done < "$TMP_RESULTS"

  echo "  ]"
  echo "}"
} > "$JSON_PATH"

{
  echo "# Team A Reliability Scorecard"
  echo
  echo "- Generated: $TOTAL_END"
  echo "- Git SHA: $GIT_SHA"
  echo "- Total duration: ${TOTAL_DURATION}s"
  echo "- Overall: $([[ $HAS_FAILURE -eq 0 ]] && echo PASS || echo FAIL)"
  echo
  echo "| Check | Status | Duration (s) | Started | Finished |"
  echo "|---|---|---:|---|---|"

  while IFS=$'\t' read -r name status duration started finished; do
    status_label="PASS"
    if [[ "$status" != "pass" ]]; then
      status_label="FAIL"
    fi
    echo "| $name | $status_label | $duration | $started | $finished |"
  done < "$TMP_RESULTS"
  echo
  echo "JSON: $JSON_PATH"
} > "$MD_PATH"

rm -f "$TMP_RESULTS"

echo
echo "Scorecard written:"
echo "- $MD_PATH"
echo "- $JSON_PATH"

if [[ $HAS_FAILURE -ne 0 ]]; then
  exit 1
fi
