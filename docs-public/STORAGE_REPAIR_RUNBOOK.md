# Storage Repair Runbook

Date: 2026-02-23  
Owner: Team A (Runtime Reliability + Data Foundation)

## Purpose

Provide operator guidance for CodexChat managed-storage repair flows, focused on Codex Home normalization/quarantine behavior and storage-root safety.

Primary evidence:
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:10`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:75`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:277`
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:127`
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:59`
- `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:67`

## Managed Paths

CodexChat storage root layout (default `~/CodexChat`):
- Projects: `<root>/projects`
- Global: `<root>/global`
- System: `<root>/system`

Repair-related paths:
- Codex Home runtime cache root: `<root>/global/codex-home`
- Quarantine root: `<root>/system/codex-home-quarantine`
- Normalization marker: `<root>/system/.codex-home-normalization-v1`
- Last repair report: `<root>/system/codex-home-last-repair-report.json`

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:31`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:59`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:63`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStoragePaths.swift:67`.

## When To Run Repair

Run Codex Home repair when:
- Runtime cache corruption or stale runtime-state symptoms are suspected.
- Startup normalization logged warnings for codex-home entries.
- User reports repeated runtime boot instability that survives restart.

Do not run repair while a turn is active.
- The app blocks manual repair during active turns.
- Runtime is intentionally stopped before forced normalization.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:79`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:267`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:273`.

## Normal Operation Flows

### Startup (non-forced) fixups

1. Run codex-home normalization if marker is missing.
2. Repair legacy general-project path and global-mod preferences.
3. Refresh projects and run legacy chat archive migration.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:10`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:17`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:47`.

### Manual repair flow

1. User invokes repair from storage settings.
2. App validates no in-flight turn and sets repair-in-progress state.
3. Runtime pool stops.
4. Forced normalization executes and writes report/marker.
5. Runtime restarts.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:75`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:260`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:277`.

## Report Interpretation

Repair writes `codex-home-last-repair-report.json` with fields:
- `reason`: startup vs manual-repair trigger.
- `forced`: whether forced normalization was used.
- `quarantinePath`: destination for moved runtime cache entries.
- `movedEntries`: entries moved out of managed codex-home runtime cache.
- `failedEntries`: entries that could not be moved.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:36`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:180`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:210`.

Operator guidance:
- `executed=false` with marker present is expected during stable startup.
- `movedEntries` non-empty indicates successful quarantine of stale runtime artifacts.
- Non-empty `failedEntries` means partial repair; inspect permissions/locks and retry manual repair.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:135`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:293`, `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:307`.

## Recovery Actions

### Case A: Repair succeeded with moved entries

1. Capture report file and quarantine path.
2. Validate runtime reconnect and thread operations.
3. Keep quarantine artifacts until stability is confirmed.

### Case B: Repair completed with warnings (`failedEntries`)

1. Inspect app logs for per-entry warning lines.
2. Confirm filesystem ownership/permissions for codex-home and quarantine paths.
3. Retry manual repair.
4. If repeated, escalate with report + diagnostics bundle.

### Case C: No quarantine path available

1. Verify whether normalization executed with no moved entries.
2. Confirm marker/report existence under `<root>/system`.
3. If startup path still fails, run manual repair once.

## Storage Root Migration Safety Notes

When changing storage root:
- Root selection is validated against nested-path and file-path hazards.
- Existing unexpected top-level entries require explicit user confirmation.
- Metadata paths are rewritten before SQLite sync, then app restart is required.

Evidence: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Storage.swift:120`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:274`, `apps/CodexChatApp/Sources/CodexChatApp/CodexChatStorageMigrationCoordinator.swift:300`.

## Escalation Checklist

Attach these artifacts when escalating a repair incident:
1. `<root>/system/codex-home-last-repair-report.json`
2. Quarantine folder contents path (if any)
3. Relevant `AppModel` storage log lines around repair execution
4. Exact timestamp and whether repair was startup or manual

Assumption: Operators have local filesystem access to the managed root and can inspect quarantine/report artifacts directly.
