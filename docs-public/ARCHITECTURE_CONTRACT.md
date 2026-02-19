# Architecture Contract

## Canonical Entry Points

- `apps/CodexChatHost` is the canonical GUI app and release source.
- `apps/CodexChatApp` provides:
- `CodexChatShared` for shared app/runtime behavior.
- `CodexChatCLI` for headless contributor tooling (`doctor`, `smoke`, `repro`).
- Release artifacts must come from host archive output, never from a SwiftPM GUI executable.

## Transition Policy

- Any temporary SwiftPM GUI fallback is migration-only and must stay undocumented.
- Fallback paths are excluded from release scripts and CI release inputs.
- Host app remains the only user-facing run and distribution path.
- Current migration artifacts in `apps/CodexChatApp/Package.swift`:
- `CodexChatDesktopFallback` (deprecated GUI fallback target)
- `CodexChatApp` (CLI compatibility executable aliasing `CodexChatCLI`)

## Boundary Rules

- Shared app/runtime behavior belongs in `CodexChatShared`.
- Host owns bundle identity, signing, entitlements, icon/assets, and lifecycle integration.
- CLI owns deterministic diagnostics and fixture replay, not GUI behavior.
- Host and CLI must remain thin shells over shared logic.

## Storage Layout (Local-First)

Default root: `~/CodexChat`

```text
<storage-root>/
  projects/
    <project>/
      chats/
        threads/
          <thread-id>.md
      artifacts/
      mods/
      memory/
        profile.md
        current.md
        decisions.md
        summary-log.md
      .agents/
        skills/
  global/
    mods/
    codex-home/
    agents-home/
  system/
    metadata.sqlite
    metadata.sqlite-wal
    metadata.sqlite-shm
    mod-snapshots/
```

## Ownership Rules

Human-editable artifacts:

- `projects/<project>/chats/threads/*.md`
- `projects/<project>/artifacts/`
- `projects/<project>/mods/`
- `projects/<project>/memory/*.md`

Internal/system-managed artifacts:

- `system/metadata.sqlite*`
- `system/mod-snapshots/`
- `system/codex-home-quarantine/`
- `projects/<project>/.agents/skills/`
- `global/codex-home/`
- `global/agents-home/`

Codex runtime ownership under `global/codex-home/`:

- Runtime internals are Codex-owned caches/state (for example `sessions/`, `archived_sessions/`, `shell_snapshots/`, `sqlite/`, `log/`, `tmp/`, `vendor_imports/`, `worktrees/`).
- CodexChat must not migrate runtime internals across homes as user data.
- CodexChat startup repair may quarantine stale runtime internals into `system/codex-home-quarantine/<timestamp>/`.
- CodexChat project archives (`projects/<project>/chats/threads/*.md`) remain independent from Codex runtime session caches.

## Reset Rules

- Project reset: delete one project directory under `projects/`.
- Full local reset: delete the storage root and relaunch.
- Do not manually edit SQLite files in `system/`.

## Migration Rules

Schema/layout changes must include:

- explicit versioning strategy
- migration path
- failure/rollback behavior
- docs updates in `docs-public/`

Codex home migration policy:

- Initial import from legacy `~/.codex` and `~/.agents` is selective and copy-if-missing only.
- Importable user artifacts: config/auth/history/credentials/instructions/memory/skills.
- Runtime internals are excluded from import and can be quarantined by normalization.
