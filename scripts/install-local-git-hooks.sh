#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_PATH="$(git -C "$ROOT" rev-parse --git-path hooks)/pre-push"
FORCE_OVERWRITE="${FORCE_OVERWRITE:-0}"
HOOK_DIR="$(dirname "$HOOK_PATH")"

mkdir -p "$HOOK_DIR"

if [[ -f "$HOOK_PATH" ]] && ! grep -q "CodexChat local reliability hook" "$HOOK_PATH"; then
  if [[ "$FORCE_OVERWRITE" != "1" ]]; then
    echo "error: pre-push hook already exists at $HOOK_PATH" >&2
    echo "Set FORCE_OVERWRITE=1 to replace it." >&2
    exit 1
  fi
fi

cat > "$HOOK_PATH" <<'HOOK'
#!/usr/bin/env bash
set -euo pipefail

# CodexChat local reliability hook
if [[ "${SKIP_LOCAL_RELIABILITY:-0}" == "1" ]]; then
  echo "[pre-push] SKIP_LOCAL_RELIABILITY=1; skipping local reliability gate."
  exit 0
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
echo "[pre-push] Running CodexChat local pre-push gate..."
make -C "$REPO_ROOT" prepush-local
HOOK

chmod +x "$HOOK_PATH"

echo "Installed pre-push hook at: $HOOK_PATH"
