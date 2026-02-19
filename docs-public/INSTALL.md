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
