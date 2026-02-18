# Public Documentation

This folder contains contributor-facing documentation tracked in git.

## Read First

1. `INSTALL.md` — local setup, build, test, run paths.
2. `CONTRIBUTING.md` — contribution workflow and guardrails.
3. `ARCHITECTURE_CONTRACT.md` — canonical host/CLI/shared boundaries and storage layout.
4. `SECURITY_MODEL.md` — safety model, secrets, and trust boundaries.
5. `RELEASE.md` — signed/notarized DMG pipeline from host archive output.

## Feature Docs

- `MODS.md` — UI mod format and precedence.
- `EXTENSIONS.md` — extension hooks, automations, inspector slot protocol (experimental).
- `MODS_SHARING.md` — creating and sharing Skills/Mods.
- `ADR-EXTENSIONS-RUNTIME.md` — extension runtime architecture decision.

## Notes

- `docs/` is private planning memory and intentionally not part of public contributor docs.
- Canonical GUI entrypoint is `apps/CodexChatHost`.
- `apps/CodexChatApp` is shared logic + contributor CLI (`CodexChatCLI`).
- Preferred onboarding command is `bash scripts/bootstrap.sh`.
- Preferred OSS smoke command is `make oss-smoke`.
