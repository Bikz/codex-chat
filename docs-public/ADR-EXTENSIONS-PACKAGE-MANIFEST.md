# ADR: Extension Package Manifest + Installer Primitive

## Status

Accepted (incremental rollout).

## Context

CodexChat extension runtime already supported hook/automation execution from `ui.mod.json`, but install/distribution concerns were not represented in a dedicated package contract.

This created friction for:

- third-party publishing/distribution
- registry-style indexing
- integrity and entrypoint validation
- reusable install flows beyond app-specific code

## Decision

1. Introduce `codex.mod.json` as a package/distribution manifest.
2. Keep `ui.mod.json` as the runtime behavior manifest.
3. Add reusable package validation in `CodexMods`:
   - schema/id/version validation
   - entrypoint path safety checks
   - package/runtime manifest consistency checks
   - declared permission superset checks
   - optional checksum verification (`integrity.uiModSha256`)
4. Add reusable `ModInstallService` in `CodexMods`:
   - source staging (local path/file URL/git URL)
   - package root resolution
   - validation before install
   - destination copy with collision-safe naming
5. Integrate app install flow (`AppModel+ModsSurface`) with `ModInstallService`.
6. Require `codex.mod.json` for install:
   - `ui.mod.json`-only packages are rejected with explicit migration guidance.

## Consequences

Positive:

- Cleaner separation of runtime vs distribution concerns.
- Better one-click install foundation for GitHub URL + local path sources.
- Stronger validation and safer defaults for third-party mod packages.
- Reusable installer for future CLI/automation paths.

Tradeoffs:

- Extension authors now need to maintain two related manifests for full vNext behavior.
- Legacy `ui.mod.json`-only packages must migrate before install.

## Follow-up

1. Add update/rollback primitives to `ModInstallService` (staging + atomic swap).
2. Add uninstall/disable UX tied to extension install records.
3. Add signed registry metadata and signature verification pipeline.
