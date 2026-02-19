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
- `projects/<project>/.agents/skills/`
- `global/codex-home/`
- `global/agents-home/`

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
