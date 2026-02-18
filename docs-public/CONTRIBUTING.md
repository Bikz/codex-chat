# Contributing

## Repo Conventions

- The default UI is two-pane (sidebar + conversation canvas). Do not add a persistent third pane.
- `docs/` is private planning memory and is intentionally ignored by git. Public docs should go in `docs-public/`.
- Prefer small, atomic commits with descriptive messages.

## Development

Run build + tests from the repo root:

```sh
pnpm -s run check
```

## Packages

- `apps/CodexChatApp`: macOS app.
- `packages/*`: modular Swift packages (Core/Infra/UI/Runtime/Skills/Memory/Mods).

