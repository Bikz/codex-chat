# Storage Handoff And Legacy Cleanup Runbook

Date: 2026-03-11  
Owner: Team A (Runtime Reliability + Data Foundation)

## Purpose

Provide operator guidance for CodexChat shared-home handoff and legacy managed-home cleanup flows.

Primary evidence:
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:10`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:75`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:277`
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:127`
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:59`
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:67`

## Active And Legacy Paths

CodexChat storage root layout (default `~/CodexChat`):
- Projects: `<root>/projects`
- Global: `<root>/global`
- System: `<root>/system`

Shared-home paths:
- Active Codex home: `CODEX_HOME` from environment when present, otherwise `~/.codex`
- Active agents home: `~/.agents`

Legacy managed paths:
- Legacy managed Codex home: `<root>/global/codex-home`
- Legacy managed agents home: `<root>/global/agents-home`
- Shared-home handoff marker: `<root>/system/.shared-codex-home-handoff-v1`
- Shared-home handoff report: `<root>/system/shared-codex-home-handoff-report.json`
- Legacy managed homes archive root: `<root>/system/legacy-managed-homes-archive/`
- Last legacy archive report: `<root>/system/legacy-managed-homes-last-archive-report.json`

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:31`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:51`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:59`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:67`.

## When To Use These Flows

Run shared-home handoff review when:
- A user expects CodexChat to pick up an existing login from another Codex client.
- Support needs to confirm which active Codex home the app is using.
- Legacy managed `~/CodexChat/global/codex-home` or `agents-home` contents still exist after upgrade.

Run legacy managed-home archive when:
- Handoff already completed successfully.
- The user wants to stop carrying the stale managed copies under `~/CodexChat/global/`.
- Support wants to remove confusion about which home is authoritative.

Do not modify the live shared `~/.codex` runtime caches as part of a CodexChat storage operation.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:82`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:90`.

## Normal Operation Flows

### Startup fixups

1. Repair legacy general-project path and global-mod preferences.
2. Repair legacy managed skill symlinks inside the old managed Codex home if needed.
3. Perform shared-home handoff from legacy managed homes into the active shared homes when the last handoff report does not already match the resolved active homes.
4. Refresh projects and run legacy chat archive migration.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:10`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:18`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:45`.

### Manual legacy cleanup flow

1. User invokes `Archive Legacy Managed Homes` from Storage settings.
2. App validates no in-flight turn and sets archive-in-progress state.
3. Runtime pool stops.
4. Legacy managed `codex-home` and `agents-home` directories are moved into a timestamped archive folder under `system/legacy-managed-homes-archive/`.
5. An archive report is written and runtime restarts.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:77`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:263`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:281`.

## Report Interpretation

Shared-home handoff writes `shared-codex-home-handoff-report.json` with fields:
- `source`: whether the active Codex home came from `CODEX_HOME` or the default user home.
- `activeCodexHomePath` and `activeAgentsHomePath`
- `legacyManagedCodexHomePath` and `legacyManagedAgentsHomePath`
- `copiedEntries`: artifacts copied into the shared homes because the destination was missing.
- `skippedEntries`: missing-source or already-present artifacts.
- `failedEntries`: artifacts that could not be copied.

Legacy cleanup writes `legacy-managed-homes-last-archive-report.json` with fields:
- `archiveRootPath`: timestamped archive directory under `system/legacy-managed-homes-archive/`
- `archivedEntries`: legacy home directories that were moved successfully
- `skippedEntries`: missing legacy roots
- `failedEntries`: legacy roots that could not be moved

Operator guidance:
- A handoff report with `copiedEntries` populated means CodexChat imported missing user artifacts into the shared homes.
- A handoff report with only `skippedEntries` is expected when the shared homes already contained the needed artifacts.
- Non-empty `failedEntries` means partial handoff or archive; inspect permissions and retry.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:95`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:177`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:217`.

## Recovery Actions

### Case A: Handoff succeeded with copied entries

1. Capture the handoff report path.
2. Validate runtime reconnect, account state, and thread operations.
3. Confirm the active shared Codex home path in Settings or Diagnostics.

### Case B: Handoff completed with warnings (`failedEntries`)

1. Inspect app logs for per-entry warning lines.
2. Confirm filesystem ownership/permissions for the active shared home and the legacy managed roots.
3. Retry startup or reopen the app to rerun handoff.
4. If repeated, escalate with report + diagnostics bundle.

### Case C: User wants to retire stale managed homes

1. Confirm handoff completed and that the shared-home path already contains the needed artifacts.
2. Run `Archive Legacy Managed Homes` once from Storage settings.
3. Capture the last archive report if support needs the final archive location.

## Storage Root Migration Safety Notes

When changing storage root:
- Root selection is validated against nested-path and file-path hazards.
- Existing unexpected top-level entries require explicit user confirmation.
- Metadata paths are rewritten before SQLite sync, then app restart is required.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:120`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:274`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:300`.

## Escalation Checklist

Attach these artifacts when escalating a storage incident:
1. `<root>/system/shared-codex-home-handoff-report.json`
2. `<root>/system/legacy-managed-homes-last-archive-report.json` if archive was run
3. Active shared Codex home path and source from Settings or Diagnostics
4. Relevant `AppModel` storage log lines around handoff or archive execution
5. Exact timestamp and whether the issue happened during startup or manual cleanup

Assumption: Operators have local filesystem access to the storage root and can inspect both the shared-home report artifacts and the active shared home path directly.
