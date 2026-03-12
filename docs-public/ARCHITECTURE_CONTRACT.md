# Architecture Contract

Related contract:
- Runtime/data reliability invariants: `docs-public/RUNTIME_DATA_RELIABILITY_CONTRACT.md`

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
  system/
    metadata.sqlite
    metadata.sqlite-wal
    metadata.sqlite-shm
    mod-snapshots/
    legacy-managed-homes-archive/
    shared-codex-home-handoff-report.json
```

Active shared runtime homes live outside the CodexChat storage root:

- Active Codex home: `CODEX_HOME` from process environment when set, otherwise `~/.codex`
- Active agents home: `~/.agents`

Legacy managed homes under `<storage-root>/global/codex-home` and `<storage-root>/global/agents-home` remain migration inputs only and are not active runtime homes.

## Ownership Rules

Human-editable artifacts:

- `projects/<project>/chats/threads/*.md`
- `projects/<project>/artifacts/`
- `projects/<project>/mods/`
- `projects/<project>/memory/*.md`

Internal/system-managed artifacts:

- `system/metadata.sqlite*`
- `system/mod-snapshots/`
- `system/shared-codex-home-handoff-report.json`
- `system/legacy-managed-homes-archive/`
- `projects/<project>/.agents/skills/`
- `global/codex-home/` (legacy managed migration source only)
- `global/agents-home/` (legacy managed migration source only)

Codex runtime ownership under the active shared Codex home:

- Runtime internals are Codex-owned caches/state (for example `sessions/`, `archived_sessions/`, `shell_snapshots/`, `sqlite/`, `log/`, `tmp/`, `vendor_imports/`, `worktrees/`).
- CodexChat must not migrate runtime internals across homes as user data.
- CodexChat must not repair, quarantine, or delete entries inside the live shared Codex home.
- CodexChat project archives (`projects/<project>/chats/threads/*.md`) remain independent from Codex runtime session caches.
- When runtime-native history import is offered, it must be a one-time copy into CodexChat-owned archives, not a live mount of the shared Codex session store.

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

- Active shared homes are `CODEX_HOME` or `~/.codex` for Codex and `~/.agents` for agents.
- One-time handoff from legacy managed homes under `<storage-root>/global/` is selective and copy-if-missing only.
- Importable user artifacts: config/auth/history/credentials/instructions/memory/skills.
- Runtime internals are excluded from handoff and remain in place until the user archives the legacy managed copies.
