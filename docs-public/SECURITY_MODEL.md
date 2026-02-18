# Security Model (High Level)

CodexChat is a local-first macOS app that integrates with the local Codex runtime. It is designed to make agentic actions legible and reviewable.

## Data Storage

- App metadata (projects, threads, preferences) is stored locally in an app-managed SQLite database under the user's Application Support directory.
- Project artifacts intended for long-term ownership (chat archives, memory notes, mods) live as files inside the user's project folder.

## Runtime Safety Controls

CodexChat applies project-level safety settings to Codex turns:

- `sandbox_mode`: controls filesystem boundaries (ex: read-only vs workspace-write vs full access).
- `approval_policy`: controls how often the runtime pauses for explicit approval.
- Network and web search can be restricted based on the project policy.

CodexChat ships with a local, readable policy note in the app bundle (`SafetyPolicy.md`) and exposes a UI path to open it.

## Secrets

- API keys are stored in macOS Keychain.
- The app avoids logging secrets and uses keychain references when persisting per-project secret records.

## UI Mods Safety

UI mods are files on disk (global and per-project).

If the agent proposes edits to files inside mod roots, CodexChat forces an explicit review step:

- A snapshot of mod roots is captured at turn start.
- At turn completion, mod-file changes trigger a mandatory review sheet.
- The user can accept changes or revert back to the snapshot.

