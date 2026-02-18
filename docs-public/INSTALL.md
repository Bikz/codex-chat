# Install / Build / Test

## Requirements

- macOS 13+ (SwiftPM platform minimum in `apps/CodexChatApp/Package.swift`).
- Xcode 16+ (Swift tools version `6.0`) or an equivalent Swift toolchain.
- Homebrew (for SwiftFormat / SwiftLint).
- Node 22+ (for `corepack` / `pnpm`; used only for workspace scripts).

## Setup

From the repo root:

```sh
corepack enable
pnpm install

brew install swiftformat swiftlint

# Optional: dead-code scan tooling.
brew install periphery
```

## Build + Test

From the repo root:

```sh
pnpm -s run check
```

## Fast Validation Loop

For the fastest local loop (format-check, lint, and a tight unit test subset):

```sh
make quick
```

## Run In Xcode

Open the app package:

```sh
open apps/CodexChatApp/Package.swift
```

Select the `CodexChatApp` scheme and run.

## Codex CLI

The app integrates the local Codex runtime via `codex app-server`.
If the `codex` binary is missing, CodexChat will show an “Install Codex” guidance view and remain usable for local-only features.
