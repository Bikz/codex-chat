# Runtime Replay and Ledger Export

CodexChat now includes local CLI workflows for deterministic thread replay and event-ledger export from user-owned archive artifacts.

## Why

1. Support deterministic local replay from persisted thread artifacts.
2. Enable reliability debugging without remote dependencies.
3. Provide a stable, machine-readable event ledger for audits and future time-travel tooling.

## Commands

Replay a thread from local archive artifacts:

```sh
cd apps/CodexChatApp
swift run CodexChatCLI replay \
  --project-path /absolute/project/path \
  --thread-id <thread-uuid> \
  --limit 100 \
  --json
```

Export a thread ledger JSON document:

```sh
cd apps/CodexChatApp
swift run CodexChatCLI ledger export \
  --project-path /absolute/project/path \
  --thread-id <thread-uuid> \
  --limit 100
```

Backfill ledgers for all archived thread artifacts in a project (idempotent, marker-based):

```sh
cd apps/CodexChatApp
swift run CodexChatCLI ledger backfill \
  --project-path /absolute/project/path \
  --json
```

By default, `ledger backfill` exports full thread history. Use `--limit <n>` only when you intentionally want a bounded replay/export window.

## Ledger Schema (v1)

Each ledger file includes:

1. `schemaVersion` (currently `1`)
2. `generatedAt` (ISO-8601 timestamp)
3. `projectPath`
4. `threadID`
5. `entries[]`

Each `entries[]` record contains:

1. `sequence` (strictly increasing)
2. `turnID`
3. `timestamp`
4. `kind` (`user_message`, `assistant_message`, `action_card`)
5. `status` (`completed`, `pending`, `failed`)
6. Optional `method`, `title`, `text`

## Integrity

Ledger export returns a SHA-256 digest of the exported JSON payload.
Use this digest in incident notes or reliability scorecards to verify artifact integrity.

## Backfill Markers

`ledger backfill` writes per-thread markers under:

`<project>/chats/threads/.ledger-backfill/<thread-id>.json`

Markers include:

1. `schemaVersion`
2. `generatedAt`
3. `projectPath`
4. `threadID`
5. `ledgerPath`
6. `entryCount`
7. `sha256`

## Migration Path

The migration and backfill sequence from transcript artifacts to authoritative event-ledger storage is tracked in:

`docs-public/planning/runtime-ledger-migration-backfill-plan.md`
