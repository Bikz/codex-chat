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
make prepush-local
pnpm -s run check
```

`prepush-local` runs `make quick`, `make oss-smoke`, and `make reliability-local` locally.
Hosted GitHub Actions is intentionally limited to quick smoke (`make quick`) only.

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

Current runtime compatibility window:

- Validated: `codex 0.114.x`
- Grace: `codex 0.113.x`
- Outside that window: startup is allowed in degraded mode, but unsupported protocol features may be gated

CodexChat targets the current app-server protocol (`approvalPolicy` values like `untrusted`/`on-request`, turn `effort`, steer `expectedTurnId` + `input[]`). If you see runtime schema mismatch errors (for example unknown variant or missing field), update Codex CLI and restart runtime.

Settings and Diagnostics surface the detected `codex` version plus the current support level. See `ADR-RUNTIME-CONTRACT-VERSIONING.md` for the checked-in compatibility policy.

## Shared Codex Home Behavior

CodexChat now uses the same active Codex home as the rest of the Codex ecosystem instead of maintaining its own runtime copy under `~/CodexChat`.

- Active Codex home:
  - `CODEX_HOME` from the launch environment when set
  - otherwise `~/.codex`
- Active agents home: `~/.agents`
- CodexChat project chat archives under `projects/<project>/chats/threads/` remain separate from Codex runtime session caches.

On startup, CodexChat performs a one-time safe handoff from legacy managed homes under `<storage-root>/global/` into the active shared homes:

- Legacy managed Codex home: `<storage-root>/global/codex-home`
- Legacy managed agents home: `<storage-root>/global/agents-home`
- Imported Codex artifacts: `config.toml`, `auth.json`, `history.jsonl`, `.credentials.json`, `AGENTS.md`, `AGENTS.override.md`, `memory.md`, and `skills/`
- Imported agents artifacts: `skills/`
- Handoff is copy-if-missing only and never overwrites files already present in the active shared homes

CodexChat does not normalize, quarantine, or delete the live shared `~/.codex` runtime caches. Settings > Storage shows:

- the active shared Codex and agents home paths
- whether the active Codex home came from `CODEX_HOME` or the default user home
- the latest handoff report path
- actions to reveal the active shared home or archive the old legacy managed copies

If you previously authenticated through another Codex client, CodexChat should pick up that login automatically from the active shared home.

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
