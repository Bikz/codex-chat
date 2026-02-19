# Install, Build, Test

## Requirements

- macOS 14+
- Xcode 16+ (Swift tools `6.0`)
- Node 22+
- Homebrew

## Setup

From repo root:

```sh
bash scripts/bootstrap.sh
```

`bootstrap.sh` validates/install tooling (`pnpm`, `swiftformat`, `swiftlint`, `gitleaks`), installs workspace deps, and runs `make quick`.

## Validate

```sh
make quick
make oss-smoke
pnpm -s run check
```

## Run In Xcode (Canonical)

```sh
open apps/CodexChatHost/CodexChatHost.xcodeproj
```

Use scheme `CodexChatHost`.

This is the canonical app run path and matches release bundle behavior (bundle ID, icon, menu metadata, permissions).

## Contributor CLI (Headless)

```sh
cd apps/CodexChatApp
swift run CodexChatCLI doctor
swift run CodexChatCLI smoke
swift run CodexChatCLI repro --fixture basic-turn
```

Use CLI commands for diagnostics/smoke/repro only. Do GUI QA in host app.
Use `CodexChatCLI` explicitly for contributor workflows; do not use SwiftPM GUI fallback targets.

## Runtime Dependency

CodexChat integrates with local Codex runtime via `codex app-server`.

If `codex` is missing, the app remains usable for local-only flows and shows setup guidance.

CodexChat targets the current app-server protocol (`approvalPolicy` values like `untrusted`/`on-request`, turn `effort`, steer `expectedTurnId` + `input[]`). If you see runtime schema mismatch errors (for example unknown variant or missing field), update Codex CLI and restart runtime.

## Managed `CODEX_HOME` Behavior

CodexChat manages runtime home at `<storage-root>/global/codex-home`.

- Codex-owned runtime internals (`sessions/`, `archived_sessions/`, `shell_snapshots/`, runtime sqlite/log/tmp caches) are treated as disposable runtime state.
- Startup migration imports only user artifacts from legacy homes: `config.toml`, auth/history files, credentials, instruction files, memory, and skills.
- Existing installs are auto-normalized once; stale runtime internals are moved to `<storage-root>/system/codex-home-quarantine/<timestamp>/`.
- Use Settings > Storage > `Repair Codex Home` to run forced repair (stop runtime, quarantine stale state, restart runtime).
- CodexChat project chat archives under `projects/<project>/chats/threads/` are separate from Codex runtime session caches.

## Voice Input Permissions

On first voice use, macOS asks for:

- Microphone
- Speech Recognition

If denied, typed input remains fully available.

## Release Packaging

```sh
make release-dmg
```

See `RELEASE.md` for signing/notarization credentials and workflow.
