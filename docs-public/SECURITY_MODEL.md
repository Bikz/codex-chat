# Security Model (High Level)

CodexChat is a local-first macOS app with explicit action visibility and user approvals for high-risk runtime actions.

## Data Storage

- App metadata (projects, threads, preferences, mappings) is stored in local SQLite under `~/CodexChat/system/metadata.sqlite`.
- User-owned project artifacts live inside each project folder (`chats/threads`, `memory`, `mods`, `artifacts`).
- Canonical thread transcripts are written to `chats/threads/<thread-id>.md` with crash-safe atomic replacement.

## Runtime Safety Controls

Project safety settings constrain runtime turns:

- `sandbox_mode`
- `approval_policy`
- `network_access`
- `web_search`

CodexChat keeps dangerous actions legible via transcript action cards and explicit approval flows.

## Shell Workspace Boundary

- Shell panes are local interactive processes and intentionally separate from runtime approval controls.
- Runtime safety settings do not sandbox shell panes.
- Untrusted projects require a one-time explicit warning acknowledgment before opening shell workspace.

## Secrets

- API keys are stored in macOS Keychain only.
- Secret material is not persisted in plain text logs.

## Trust-Gated Rendering

- Assistant Markdown rendering is trust-gated for external content.
- Untrusted projects block outbound `http/https` links and remote images by default.

## UI Mods Safety

When runtime proposes edits in mod roots, CodexChat enforces review:

- capture pre-turn snapshot
- show mandatory review sheet on completion
- allow explicit accept or full revert

## Extension Runtime Safety

`ui.mod.json` schemaVersion 1 mods can define hooks and automations. These capabilities are permission-gated.

- Permission keys: `projectRead`, `projectWrite`, `network`, `runtimeControl`, `runWhenAppClosed`
- Privileged permissions are prompted on first use per mod.
- Background automations require:
  - per-mod `runWhenAppClosed` permission
  - one-time global background automation permission
- Worker execution uses isolated subprocess invocation with hard timeouts and output caps.
- Artifact writes are confined to project roots; traversal outside project root is rejected.
- Extension diagnostics sanitize token-like secret patterns before logging.

## Native Computer Actions Safety

CodexChat supports native macOS computer actions for personal workflows (desktop cleanup, calendar lookups, and message drafting/sending).

- Preview-first execution is mandatory for externally visible or file-changing actions.
- Execution requires explicit confirmation from the preview sheet before the action runs.
- Action execution is bound to the same run context as its preview artifact.
- Desktop cleanup only performs move operations in v1 (no permanent delete) and stores undo manifests.
- Calendar access is read-only in v1.
- Messages send requires explicit draft preview and send confirmation.
- Permission grants/denials and run outcomes are persisted locally in metadata SQLite.

## Executable Mods Guardrail

To reduce non-vetted script risk, CodexChat applies an advanced unlock gate for executable mod behavior:

- Existing installs preserve prior behavior after migration.
- New installs default to locked advanced executable mods.
- Non-vetted mods using hooks/automations stay disabled until explicit unlock.
- First-party vetted packs under `mods/first-party` remain available without custom unlock.
