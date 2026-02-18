# Contributing

## Repo Conventions

- The default UI is two-pane (sidebar + conversation canvas). Do not add a persistent third pane.
- `docs/` is private planning memory and is intentionally ignored by git. Public docs should go in `docs-public/`.
- Prefer small, atomic commits with descriptive messages.
- Keep the repo steerable: when a Swift file grows beyond ~500 LOC, split it into focused types or `TypeName+Feature.swift` extensions.
- Do not log secrets. Never print API keys/tokens to stdout, logs, or test snapshots.

## Development

Run build + tests from the repo root:

```sh
corepack enable
pnpm install

pnpm -s run check
```

For the fastest local loop:

```sh
make quick
```

## Packages

- `apps/CodexChatApp`: macOS app.
- `packages/*`: modular Swift packages (Core/Infra/UI/Runtime/Skills/Memory/Mods).
