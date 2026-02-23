# Public Documentation

This folder contains contributor-facing documentation tracked in git.

## Read First

1. `INSTALL.md` — local setup, build, test, run paths.
2. `../CONTRIBUTING.md` — canonical contribution workflow and guardrails.
3. `ARCHITECTURE_CONTRACT.md` — canonical host/CLI/shared boundaries and storage layout.
4. `SECURITY_MODEL.md` — safety model, secrets, and trust boundaries.
5. `RELEASE.md` — signed/notarized DMG pipeline from host archive output.

## Feature Docs

- `MODS.md` — UI mod format and precedence.
- `MODS_SHARING.md` — canonical builder guide for creating/sharing Skills/Mods, including extension schema/protocol (experimental).
- `PERSONAL_ACTIONS.md` — native macOS personal actions, adaptive intent routing, and preview/confirm safety model.
- `DEVELOPER_AGENT_WORKFLOWS.md` — worker trace, role/profile builder, and dependency-aware plan runner primitives.
- `CODEX_APP_SERVER_RESPONSE_TAXONOMY.md` — complete inventory of app-server response types, decode paths, and current UX treatment.
- `RUNTIME_LEDGER_REPLAY.md` — deterministic local replay and thread-ledger export workflow.
- `RUNTIME_POLICY_AS_CODE.md` — tracked runtime safety policy validation workflow.
- `RUNTIME_RELIABILITY_SLO_DRAFT.md` — draft SLI/SLO targets for runtime/data reliability.
- `RUNTIME_RELIABILITY_BUNDLE.md` — one-command local reliability diagnostics bundle workflow.
- `EXTENSIONS.md` — compatibility landing page linking to canonical `MODS_SHARING.md` sections.
- `ADR-EXTENSIONS-RUNTIME.md` — extension runtime architecture decision.
- `EXTENSIONS_SPEC_VNEXT.md` — proposed package/runtime extension spec for ecosystem scaling.
- `EXTENSIONS_QUICKSTART.md` — quickstart for creating/installing extension packages.
- `EXTENSIONS_CURRENT_STATE_AUDIT.md` — architecture + DX audit and prioritized roadmap.
- `ADR-EXTENSIONS-PACKAGE-MANIFEST.md` — package manifest + installer architecture decision.
- `ADR-MODS-SCHEMA-RESET-V1.md` — clean-slate `ui.mod.json` schema reset + breaking-change policy.
- `ADR-MODS-BAR-ACTIONS-AND-GITHUB-SUBDIR-INSTALL.md` — Mods bar actions + GitHub subdirectory install decision.

## Notes

- `docs/` is private planning memory and intentionally not part of public contributor docs.
- `mods/first-party/` contains first-party exemplar mod packages; third-party mods should live in external repos.
- Canonical GUI entrypoint is `apps/CodexChatHost`.
- `apps/CodexChatApp` is shared logic + contributor CLI (`CodexChatCLI`).
- Preferred onboarding command is `bash scripts/bootstrap.sh`.
- Preferred OSS smoke command is `make oss-smoke`.
- Shell workspace UI favors minimal chrome: icon-only multi-shell rail on the left, near full-bleed terminal space on the right, and monochrome shell surfaces (white/light, black/dark).
- Live activity traces use compact one-word status labels by default and only expand into a trace box when rich trace details are available.
