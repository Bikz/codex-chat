# CodexChat

CodexChat is a local-first macOS SwiftUI chat app that integrates the local Codex runtime (`codex app-server`) so users can safely run agentic tasks from a chat-first interface.

## Product Contract

- UI is strictly two-pane: sidebar (projects + threads) and conversation canvas.
- Do not ship a persistent third pane in current releases.
- Capability discovery and invocation happen through the main composer (typed or voice).

## Architecture

- `apps/CodexChatHost`: canonical GUI app target (`com.codexchat.app`) for local QA/dev and release distribution.
- `apps/CodexChatApp`: shared app/runtime module (`CodexChatShared`) and contributor CLI (`CodexChatCLI`).
- `packages/*`: modular Swift packages (`Core`, `Infra`, `UI`, `CodexKit`, `Skills`, `Memory`, `Mods`).

## Requirements

- macOS 14+
- Xcode 16+ (Swift tools `6.0`)
- Node 22+
- Homebrew
- SwiftFormat, SwiftLint, gitleaks

## Setup

```sh
corepack enable
pnpm install
brew install swiftformat swiftlint gitleaks
```

## Validation

```sh
make quick
pnpm -s run check
```

## Run Locally

Primary run path (canonical GUI behavior):

```sh
open apps/CodexChatHost/CodexChatHost.xcodeproj
```

Use the `CodexChatHost` scheme.

Contributor CLI (headless diagnostics/repro):

```sh
cd apps/CodexChatApp
swift run CodexChatCLI doctor
swift run CodexChatCLI smoke
swift run CodexChatCLI repro --fixture basic-turn
```

## Docs

- `docs-public/README.md`
- `docs-public/INSTALL.md`
- `docs-public/CONTRIBUTING.md`
- `docs-public/ARCHITECTURE_CONTRACT.md`
- `docs-public/SECURITY_MODEL.md`
- `docs-public/MODS.md`
- `docs-public/MODS_SHARING.md`
- `docs-public/RELEASE.md`

## License

MIT. See `LICENSE`.
