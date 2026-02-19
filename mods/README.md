# Mods Repository Policy

This folder contains first-party exemplar mods for CodexChat.

## Scope

- `mods/first-party/*` is reserved for first-party maintained examples and production-ready reference mods.
- Third-party mods should be distributed from external repositories (GitHub) and installed in CodexChat via:
  - local folder path, or
  - public GitHub URL.

## Third-Party Submission Model

- Do not submit third-party executable mods directly into this repository.
- Submit ecosystem docs/ADR/spec improvements here.
- Share third-party mods as public GitHub repositories for one-click install.

## Contract

- Every first-party mod package in this folder must include:
  - `codex.mod.json` (required)
  - `ui.mod.json` (`schemaVersion: 1`)
- `uiSlots.modsBar` is the only supported Mods bar slot key.
- Legacy `uiSlots.rightInspector` is unsupported.
