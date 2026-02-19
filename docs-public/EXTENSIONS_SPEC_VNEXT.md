# CodexChat Extension Spec vNext (Draft)

## Goals

- Make third-party mods easy to build, distribute, and one-click install.
- Keep the runtime local-first, explicit, and safety-gated.
- Preserve product constraints: two-pane IA, no persistent third pane.

## Package Layout

Each distributable extension package should include:

```text
<mod-root>/
  codex.mod.json       # package/distribution manifest (vNext)
  ui.mod.json          # runtime config (schemaVersion: 1)
  scripts/             # optional handlers
  README.md            # optional human docs
```

`ui.mod.json` remains the runtime contract.
`codex.mod.json` becomes the install/distribution contract.

## `codex.mod.json` Schema (v1)

```json
{
  "schemaVersion": 1,
  "id": "acme.thread-summary",
  "name": "Thread Summary",
  "version": "1.0.0",
  "description": "One-line summaries in modsBar.",
  "author": "Acme",
  "license": "MIT",
  "repository": "https://github.com/acme/thread-summary",
  "entrypoints": {
    "uiMod": "ui.mod.json"
  },
  "permissions": ["projectRead"],
  "compatibility": {
    "platforms": ["macos"],
    "minCodexChatVersion": "0.1.0"
  },
  "integrity": {
    "uiModSha256": "sha256:<hex>"
  }
}
```

## Required Validation Rules

1. `schemaVersion` must be supported (`1` for now).
2. `id` must be stable, lowercase, package-safe (`[a-z0-9._-]`).
3. `version` must be semver-like (`x.y.z` with optional suffix).
4. `entrypoints.uiMod` must be a safe relative path (no absolute path, no `..` traversal).
5. `id/name/version` in `codex.mod.json` must match `ui.mod.json.manifest`.
6. `permissions` must declare every permission requested by hooks/automations in `ui.mod.json`.
7. If `integrity.uiModSha256` is present, checksum must match `ui.mod.json`.
8. If `compatibility.platforms` is present, it must include `macos`, `darwin`, or `*`.

Notes:

- `integrity.uiModSha256` is optional.
- Generated sample packages intentionally leave `integrity` unset by default to avoid accidental checksum drift during iteration.

## Capability Model

Capabilities are still runtime-driven by `ui.mod.json`:

- Commands: extension-provided slash-command packs (future explicit surface).
- Events: `thread.started`, `turn.started`, `assistant.delta`, `action.card`, `approval.requested`, `modsBar.action`, `turn.completed`, `turn.failed`, `transcript.persisted`.
- UI hooks: `uiSlots.modsBar` for modsBar rendering.
- Tool hooks: handler subprocesses via stdio JSONL protocol.
- Storage/network: governed by permission keys declared in `permissions` and prompted at runtime.

`modsBar` worker output supports:

- `scope`: `thread` (default) or `global`
- `actions`: typed actions (`emitEvent`, `promptThenEmitEvent`, `composer.insert`, `composer.insertAndSend`)

Permission keys:

- `projectRead`
- `projectWrite`
- `network`
- `runtimeControl`
- `runWhenAppClosed`

## Security / Trust Model

1. Install-time validation:
- Validate package manifest + runtime manifest consistency.
- Validate path safety and optional checksum integrity.

2. Runtime permission gating:
- First-use prompts remain mandatory for privileged actions.
- Background automation remains separately gated by global consent + per-mod permission.

3. Process isolation:
- Handlers run as subprocesses with timeout and output caps.

4. Artifact boundaries:
- Extension artifact writes remain confined to project root.

## Versioning And Compatibility Policy

- `codex.mod.json.schemaVersion` governs package install semantics.
- `ui.mod.json.schemaVersion` governs runtime feature semantics.
- Runtime compatibility:
  - `ui.mod.json` must use `schemaVersion: 1`.
  - Legacy `schemaVersion: 2` and `uiSlots.rightInspector` are rejected with migration errors.
- Package compatibility:
  - `codex.mod.json` is required.
  - Packages missing `codex.mod.json` are rejected with migration guidance.

## Error Handling And Fallback

Install should fail fast for:

- missing `codex.mod.json`
- invalid manifest schema/id/version
- unsupported `ui.mod.json` schema version
- unsupported legacy key (`uiSlots.rightInspector`)
- unsafe entrypoint path
- undeclared requested permissions
- checksum mismatch
- ambiguous package root

## Telemetry And Diagnostics (Non-sensitive)

Recommended install/runtime diagnostics:

- package id/version/source host
- validation stage and failure reason
- permission keys requested/granted/denied
- hook/automation execution status (duration, timeout, exit status)

Must not include:

- secrets
- auth headers/tokens
- raw sensitive file contents

## One-Click Install Architecture (Target)

1. Source intake:
- local folder path
- GitHub repo URL (including GitHub `tree` subdirectory URL)
- GitHub `blob` URLs are rejected with migration guidance to use `tree` URLs

2. Fetch/stage:
- Clone/download into temporary staging directory.

3. Validate:
- `codex.mod.json` + `ui.mod.json` consistency and integrity checks.

4. Permission review:
- Show requested permissions before first privileged execution.

5. Install:
- Copy package into scope root (global/project), write install metadata, auto-enable.

6. Recoverability:
- Safe update path with rollback on failure.
