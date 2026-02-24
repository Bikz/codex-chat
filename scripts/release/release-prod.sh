#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REMOTE="${REMOTE:-origin}"
WORKFLOW_FILE="${WORKFLOW_FILE:-release-dmg.yml}"
RELEASE_TIMEOUT_MINUTES="${RELEASE_TIMEOUT_MINUTES:-45}"
RUN_DISCOVERY_TIMEOUT_SECONDS="${RUN_DISCOVERY_TIMEOUT_SECONDS:-240}"
POLL_INTERVAL_SECONDS="${POLL_INTERVAL_SECONDS:-15}"
ENABLE_LOCAL_FALLBACK="${ENABLE_LOCAL_FALLBACK:-1}"

VERSION="${VERSION:-${1:-}}"

if [[ "$#" -gt 1 ]]; then
  echo "usage: $0 [version]" >&2
  exit 1
fi

fail() {
  echo "error: $*" >&2
  exit 1
}

log() {
  printf '[release-prod] %s\n' "$*"
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "required command missing: $1"
  fi
}

validate_version() {
  local version="$1"
  if ! [[ "$version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    fail "version must match v<major>.<minor>.<patch> (got: $version)"
  fi
}

release_exists() {
  gh release view "$VERSION" >/dev/null 2>&1
}

release_has_required_assets() {
  if ! release_exists; then
    return 1
  fi

  local is_draft
  local is_prerelease
  local has_dmg
  local has_sha

  is_draft="$(gh release view "$VERSION" --json isDraft --jq '.isDraft')"
  is_prerelease="$(gh release view "$VERSION" --json isPrerelease --jq '.isPrerelease')"
  has_dmg="$(gh release view "$VERSION" --json assets --jq '.assets | any(.name == "CodexChat-'"$VERSION"'.dmg")')"
  has_sha="$(gh release view "$VERSION" --json assets --jq '.assets | any(.name == "CodexChat-'"$VERSION"'.dmg.sha256")')"

  [[ "$is_draft" == "false" && "$is_prerelease" == "false" && "$has_dmg" == "true" && "$has_sha" == "true" ]]
}

resolve_version() {
  if [[ -n "$VERSION" ]]; then
    validate_version "$VERSION"
    return
  fi

  VERSION="$($ROOT/scripts/release/next-version.sh v)"
  validate_version "$VERSION"
}

remote_tag_commit() {
  local tag="$1"
  local commit
  commit="$(git ls-remote --refs "$REMOTE" "refs/tags/$tag^{}" | awk '{print $1}' | head -n 1)"
  if [[ -n "$commit" ]]; then
    echo "$commit"
    return
  fi

  git ls-remote --refs "$REMOTE" "refs/tags/$tag" | awk '{print $1}' | head -n 1
}

ensure_tag_exists_remote() {
  local remote_sha
  local local_sha
  remote_sha="$(remote_tag_commit "$VERSION")"

  if [[ -n "$remote_sha" ]]; then
    log "Remote tag already exists: $VERSION"
    local_sha="$(git rev-list -n 1 "$VERSION" 2>/dev/null || true)"
    if [[ -z "$local_sha" || "$local_sha" != "$remote_sha" ]]; then
      git fetch -f "$REMOTE" "refs/tags/$VERSION:refs/tags/$VERSION"
    fi
    return
  fi

  if ! git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
    log "Creating local tag $VERSION on HEAD"
    git tag "$VERSION"
  fi

  log "Pushing tag $VERSION to $REMOTE"
  git push "$REMOTE" "refs/tags/$VERSION"
}

find_release_run_for_sha() {
  local sha="$1"
  gh run list \
    --workflow "$WORKFLOW_FILE" \
    --limit 50 \
    --json databaseId,headSha,event \
    --jq '.[] | select(.headSha == "'"$sha"'" and .event == "push") | .databaseId' \
    | tail -n 1
}

wait_for_release_run_id() {
  local sha="$1"
  local deadline=$(( $(date +%s) + RUN_DISCOVERY_TIMEOUT_SECONDS ))

  while (( $(date +%s) <= deadline )); do
    local run_id
    run_id="$(find_release_run_for_sha "$sha" || true)"
    if [[ -n "$run_id" ]]; then
      echo "$run_id"
      return 0
    fi

    sleep "$POLL_INTERVAL_SECONDS"
  done

  return 1
}

print_failed_run_diagnostics() {
  local run_id="$1"

  log "Collecting failure diagnostics for run $run_id"
  gh run view "$run_id" --json url,status,conclusion,name,headSha,workflowName || true
  gh run view "$run_id" --log-failed || true
}

wait_for_run_completion() {
  local run_id="$1"
  local deadline=$(( $(date +%s) + (RELEASE_TIMEOUT_MINUTES * 60) ))

  while (( $(date +%s) <= deadline )); do
    local status
    local conclusion

    status="$(gh run view "$run_id" --json status --jq '.status' 2>/dev/null || true)"
    conclusion="$(gh run view "$run_id" --json conclusion --jq '.conclusion' 2>/dev/null || true)"

    if [[ "$status" == "completed" ]]; then
      if [[ "$conclusion" == "success" ]]; then
        log "CI release workflow succeeded."
        return 0
      fi

      log "CI release workflow completed with conclusion: ${conclusion:-unknown}"
      print_failed_run_diagnostics "$run_id"
      return 1
    fi

    log "Waiting for CI run $run_id (status: ${status:-unknown})"
    sleep "$POLL_INTERVAL_SECONDS"
  done

  log "Timed out waiting ${RELEASE_TIMEOUT_MINUTES}m for CI run $run_id"
  print_failed_run_diagnostics "$run_id"
  return 2
}

build_local_release() {
  local temp_worktree
  local worktree_dir

  log "Running local notarized build for $VERSION from isolated tag worktree"
  mkdir -p "$ROOT/.release-worktrees"
  temp_worktree="$(mktemp -d "$ROOT/.release-worktrees/$VERSION.XXXXXX")"
  worktree_dir="$ROOT/.release-worktrees/${VERSION}.worktree"
  rm -rf "$worktree_dir"
  mv "$temp_worktree" "$worktree_dir"

  if ! git worktree add --detach "$worktree_dir" "$VERSION" >/dev/null; then
    rm -rf "$worktree_dir"
    fail "failed to create temporary release worktree for $VERSION"
  fi

  if ! (
    cd "$worktree_dir"
    DIST_DIR="$ROOT/dist" VERSION="$VERSION" ./scripts/release/build-notarized-dmg.sh
  ); then
    git worktree remove --force "$worktree_dir" >/dev/null 2>&1 || true
    rm -rf "$worktree_dir"
    fail "local fallback build failed for $VERSION"
  fi

  git worktree remove --force "$worktree_dir" >/dev/null 2>&1 || true
  rm -rf "$worktree_dir"
}

publish_local_assets() {
  local dmg_path="$ROOT/dist/CodexChat-$VERSION.dmg"
  local sha_path="$dmg_path.sha256"

  [[ -f "$dmg_path" ]] || fail "missing artifact: $dmg_path"
  [[ -f "$sha_path" ]] || fail "missing artifact: $sha_path"

  if ! release_exists; then
    log "Creating GitHub release $VERSION"
    gh release create "$VERSION" \
      "$dmg_path" \
      "$sha_path" \
      --verify-tag \
      --title "$VERSION" \
      --notes "Production release $VERSION"
    return
  fi

  log "Uploading artifacts to existing release $VERSION (idempotent --clobber)"
  gh release upload "$VERSION" "$dmg_path" "$sha_path" --clobber
}

verify_release() {
  local release_url

  if ! release_has_required_assets; then
    fail "release $VERSION is missing required assets or is marked draft/prerelease"
  fi

  release_url="$(gh release view "$VERSION" --json url --jq '.url')"
  log "Release verification passed: $release_url"

  gh release view "$VERSION" --json assets --jq '.assets[].name' \
    | sed 's/^/[release-prod] asset: /'
}

main() {
  require_command git
  require_command gh

  git fetch "$REMOTE" --tags --force
  resolve_version
  log "Starting production release for $VERSION"

  if release_has_required_assets; then
    log "Release already complete for $VERSION; nothing to do."
    verify_release
    return 0
  fi

  ensure_tag_exists_remote

  local target_sha
  target_sha="$(git rev-list -n 1 "$VERSION")"

  local run_id
  local ci_result
  ci_result="fallback"

  if run_id="$(wait_for_release_run_id "$target_sha")"; then
    local run_url
    run_url="$(gh run view "$run_id" --json url --jq '.url' 2>/dev/null || true)"
    log "Found CI release workflow run: $run_id ${run_url:-}"

    if wait_for_run_completion "$run_id"; then
      ci_result="success"
    else
      ci_result="failed"
    fi
  else
    log "No CI run found within discovery window (${RUN_DISCOVERY_TIMEOUT_SECONDS}s)."
    ci_result="failed"
  fi

  if [[ "$ci_result" != "success" ]]; then
    if [[ "$ENABLE_LOCAL_FALLBACK" != "1" ]]; then
      fail "CI release did not succeed and local fallback is disabled (ENABLE_LOCAL_FALLBACK=0)"
    fi

    log "Falling back to local signed/notarized release publish."
    build_local_release
    publish_local_assets
  fi

  verify_release
  log "Release completed for $VERSION"
}

main "$@"
