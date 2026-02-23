# User Journeys

## Scope
End-to-end journeys below cover primary happy paths and key failure/edge paths observed in app code, package contracts, and tests.

Conventions:
- `States` always list `empty`, `loading`, `error`, `success`.
- `Telemetry points` refer to current local observability surfaces (logs/action cards/perf traces/persistence), not remote analytics.
- `Assumption` indicates behavior inferred from tests/usage patterns.

---

## 1) First Launch to First Usable Chat
- Journey name: Onboard and activate runtime
- Trigger: User opens app with no active session
- Happy-path steps:
1. App runs startup critical phase (projects/config/preferences/context).
2. Onboarding appears if runtime/auth is not ready.
3. User signs in (ChatGPT or API key).
4. Runtime connects; onboarding completes.
5. General project draft chat is activated and composer is usable.
- States:
  - Empty: no selected thread, onboarding cards visible
  - Loading: startup metadata load, runtime starting, login polling
  - Error: startup failure/runtime unavailable/sign-in failure message
  - Success: connected runtime + active draft thread
- Failure recovery:
  - Runtime missing: install with Homebrew/copy command/restart runtime.
  - Browser sign-in timeout: explicit fallback messaging to restart or use device-code login.
  - Invalid config: fallback to built-in defaults and continue startup.
- Telemetry points:
  - `appendLog` startup and auth messages
  - runtime status + runtime issue state
  - account status banners
  - performance spans around startup/selection paths
- Assumption: onboarding completion intentionally seeds General draft chat to avoid blank-state dead end.

## 2) Create or Select Project + Apply Safety
- Journey name: Project setup and trust controls
- Trigger: User creates project or opens project settings
- Happy-path steps:
1. User creates/chooses project from sidebar.
2. User sets trust state and safety options (sandbox, approvals, network, web search).
3. Dangerous combinations require confirmation phrase.
4. Settings are persisted and runtime safety configuration reflects project policy.
- States:
  - Empty: no project selected
  - Loading: project/thread refresh after selection
  - Error: repository update failure
  - Success: project selected with persisted safety settings
- Failure recovery:
  - Non-git project: explicit message before git-only operations.
  - Dangerous config typo: confirmation mismatch keeps prior settings.
- Telemetry points:
  - project status messages + logs
  - preference/project repository writes
  - selection-transition performance spans

## 3) Send a Turn and Receive Streaming Output
- Journey name: Text/attachment/skill prompt execution
- Trigger: User presses send in composer
- Happy-path steps:
1. User message is appended locally.
2. Runtime thread mapping is ensured (or created).
3. Turn starts; deltas stream into conversation.
4. Runtime actions/approvals surface as cards.
5. Turn completes and transcript is persisted/indexed.
- States:
  - Empty: no transcript entries yet
  - Loading: active turn/live activity row
  - Error: turn start error/action card/error status
  - Success: assistant response + persisted turn archive
- Failure recovery:
  - Stale runtime thread ID: mapping invalidated, thread recreated, turn retried once.
  - Turn start failure: checkpoint marked failed + user-visible error action card.
- Telemetry points:
  - action cards (`turn/started`, `turn/completed`, `turn/error`)
  - `thread.persistCompletedTurn` performance span
  - chat archive checkpoints + transcript files
  - search index writes

## 4) Runtime Approval Decision Flow
- Journey name: Approval-gated action execution
- Trigger: Runtime emits `approval.requested`
- Happy-path steps:
1. Approval request is routed to selected thread (or unscoped queue fallback).
2. Inline/sheet approval UI shows reason, command, file changes, risk cues.
3. User declines, approves once, or approves for session.
4. Decision is sent; queue advances.
- States:
  - Empty: no pending approvals
  - Loading: decision in-flight
  - Error: failed decision submission
  - Success: approval resolved and auto-drain resumes
- Failure recovery:
  - Missing thread mapping: request remains in unscoped queue until mapping resolves.
  - Runtime interruption: stale approval state is reset with explicit user message.
- Telemetry points:
  - approval status message/logs
  - approval action cards
  - approval state machine transitions

## 5) Runtime Termination and Recovery
- Journey name: Mid-session runtime failure handling
- Trigger: runtime termination/stderr critical events
- Happy-path steps:
1. Runtime issue is surfaced in transcript/logs.
2. App flushes buffered conversation updates.
3. Repair suggestion cards may appear for known failure classes.
4. User restarts runtime and resumes conversation.
- States:
  - Empty: no runtime errors
  - Loading: runtime restarting
  - Error: runtime status `.error` with issue message
  - Success: connected runtime, queue resumes
- Failure recovery:
  - Known rollout-path warnings get targeted repair suggestions.
  - Restart path avoids false “terminated” noise for intentional restarts.
- Telemetry points:
  - sanitized stderr thread logs
  - runtime repair suggestion action cards
  - runtime pool worker health metrics

## 6) Search and Rehydrate Past Thread
- Journey name: Find and reopen historical chat
- Trigger: User types sidebar search query
- Happy-path steps:
1. Search query debounces and executes against local index.
2. User selects result.
3. Project/thread selection updates, transcript rehydrates, thread prewarm runs.
- States:
  - Empty: no query
  - Loading: search in progress
  - Error: index/query failure
  - Success: selected thread opened at current state
- Failure recovery:
  - Missing index repository: explicit “search unavailable” error state.
  - Selection transition cancellation guards prevent stale UI mutations.
- Telemetry points:
  - `thread.selectSearchResult` performance span
  - search state transitions + error logs

## 7) Follow-up Queue with Steer/Retry
- Journey name: Convert suggestions into queued work
- Trigger: Assistant follow-up suggestions or user-queued follow-up
- Happy-path steps:
1. Suggestions are persisted in queue with ordering and dispatch mode.
2. User edits/reorders/steers/deletes.
3. Steered follow-up starts as turn; queue entry clears on success.
- States:
  - Empty: no queue items
  - Loading: queue refresh/update
  - Error: failed steer/queue mutation
  - Success: follow-up executed or updated
- Failure recovery:
  - Steer unsupported/fails: item can be marked failed and retried.
  - Queue deletion/update errors leave actionable status/log output.
- Telemetry points:
  - follow-up repository writes
  - follow-up status message
  - turn start/completion action cards

## 8) Skill Install, Enable, and Use in Composer
- Journey name: Skill lifecycle and invocation
- Trigger: User opens Skills tab or uses `$skill` autocomplete
- Happy-path steps:
1. Local and catalog skills load.
2. User installs skill (global/project) and enables target scope.
3. User inserts or autocompletes `$skill` in composer.
4. Skill context is injected into runtime turn.
- States:
  - Empty: no skills discovered / no query
  - Loading: discover/install/catalog fetch
  - Error: install/update/catalog failure
  - Success: skill enabled and selectable in composer
- Failure recovery:
  - Missing project for project-scope install: explicit guardrail message.
  - Update unavailable when metadata/source missing: downgraded to clear warning.
- Telemetry points:
  - skill status/log messages
  - enablement repository state
  - catalog fetch state

## 9) Mod Install + Mods Bar Interaction
- Journey name: Install/enable mod and execute mods bar actions
- Trigger: User installs mod from path/URL/catalog and toggles mods bar
- Happy-path steps:
1. Mod package validates (`codex.mod.json` + `ui.mod.json`).
2. Mod installs and is discovered in scope.
3. User enables global/project mod.
4. User can open mods bar from any selected-project conversation context (including new draft chats before first message).
5. Mods bar output appears; user actions route to composer/events/native actions.
6. Visibility + mode persist across thread switches and new drafts (`rail`/`peek`/`expanded` with reopen restore behavior).
- States:
  - Empty: no active mods/mods bar disabled
  - Loading: mod refresh/install operation
  - Error: validation/install/permission failures
  - Success: mod active and mods bar actions functional
- Failure recovery:
  - Invalid schema/legacy keys: explicit migration guidance.
  - Advanced executable mod lock blocks non-vetted executable behavior until unlocked.
  - On reopen from hidden while in `rail`, app restores last open non-rail panel mode for usability.
- Telemetry points:
  - extension install records + enablement
  - mod status/log messages
  - emitted extension events (`modsBar.action` etc.)

## 10) Native Personal Action with Preview + Confirmation
- Journey name: Execute computer action safely
- Trigger: User prompt/adaptive intent/mods bar native action
- Happy-path steps:
1. Action preview is generated first.
2. If required, inline approval requires explicit confirmation.
3. Permission check runs and execution occurs.
4. Outcome is persisted as action run and reflected in transcript card.
- States:
  - Empty: no pending action preview
  - Loading: preview/execution in progress
  - Error: validation/permission/execution failure
  - Success: executed (or queued for approval) with summary
- Failure recovery:
  - Permission denied with known category -> permission recovery notice + deep-link guidance.
  - Desktop cleanup supports undo through persisted manifest.
- Telemetry points:
  - `computer_action_runs` and permission records
  - computer action status messages/logs
  - transcript action cards (`preview`, `execute`, `undo`)

## 11) Voice Capture to Prompt Text
- Journey name: Dictate prompt into composer
- Trigger: User presses mic button or shortcut
- Happy-path steps:
1. App requests mic/speech permissions.
2. Recording starts and elapsed timer updates.
3. User stops capture (or timeout).
4. Transcription appends into composer.
- States:
  - Empty: idle voice state
  - Loading: requesting permission / transcribing
  - Error: denied/failed/no-speech
  - Success: transcript inserted and state reset to idle
- Failure recovery:
  - Session ID gating prevents stale async callbacks from mutating newer sessions.
  - Cancel path is idempotent and clears pending work.
- Telemetry points:
  - voice state + status message
  - debug logs in debug builds

## 12) Memory Authoring + Retrieval
- Journey name: Maintain project memory and inject snippets
- Trigger: User opens Memory canvas or memory snippet sheet
- Happy-path steps:
1. Memory structure is ensured under project `memory/`.
2. User edits/saves files and configures auto-write mode.
3. User searches (keyword/semantic) and inserts snippet into composer.
4. Completed turns optionally append summary/key facts.
- States:
  - Empty: no project selected / idle search
  - Loading: file load/search
  - Error: read/write/index/search errors
  - Success: saved memory + inserted snippets + auto summary updates
- Failure recovery:
  - Unsaved-change guard before switching files.
  - Semantic mode can fail gracefully when embeddings unavailable.
- Telemetry points:
  - memory status messages
  - memory file writes and semantic index rebuilds
  - turn persistence path invoking memory auto-summary

## 13) Shell Workspace for Active Project
- Journey name: Open project-scoped terminal sessions
- Trigger: User toggles shell workspace toolbar action
- Happy-path steps:
1. For trusted projects (or acknowledged untrusted warning), workspace opens.
2. Session auto-creates if none exists.
3. User splits panes, changes focus, closes panes/sessions.
- States:
  - Empty: no project or no sessions
  - Loading: initial session creation
  - Error: trust gating / unavailable context
  - Success: running shell panes with per-project state
- Failure recovery:
  - Untrusted projects show one-time warning; user can decline without opening workspace.
  - Closing last pane auto-closes session cleanly.
- Telemetry points:
  - project status messages
  - in-memory shell workspace state transitions

## 14) Plan Runner Orchestration
- Journey name: Execute dependency-aware implementation plans
- Trigger: User opens plan runner and starts run
- Happy-path steps:
1. Plan text/path loads and parses into tasks.
2. Scheduler finds unblocked batch (parallel when enabled).
3. Batch is dispatched as turn prompt(s).
4. Completion markers update task status until plan finishes.
5. Plan run/task state persists for thread.
- States:
  - Empty: no plan loaded / no persisted run
  - Loading: parsing/dispatching/waiting for turn completion
  - Error: parse cycle/timeout/missing completion markers
  - Success: all tasks marked complete and run status completed
- Failure recovery:
  - Cycle detection blocks start with explicit error.
  - Marker-missing path falls back only for single-task batches; otherwise fails clearly.
- Telemetry points:
  - plan run action cards (`batch`, `completed`, `failed`)
  - `plan_runs` + `plan_run_tasks` persistence
  - plan runner status/log messages

## 15) Diagnostics and Support Export
- Journey name: Inspect runtime health and export diagnostic bundle
- Trigger: User opens diagnostics from menu/toolbar
- Happy-path steps:
1. Diagnostics view shows runtime status, pool metrics, perf snapshot, logs.
2. User exports diagnostics bundle.
3. Bundle path is copied for sharing.
- States:
  - Empty: no logs/perf samples yet
  - Loading: perf snapshot refresh loop
  - Error: export failure
  - Success: bundle exported + path copied
- Failure recovery:
  - Export cancellation handled as non-failure.
  - Error surfaced in account status + logs.
- Telemetry points:
  - diagnostics logs
  - `PerformanceTracer` snapshots
  - diagnostics bundle artifact creation

---

## Cross-Journey Recovery Patterns
1. Selection transitions are generation-scoped to cancel stale async mutations.
2. Runtime thread/turn mapping is reconciled across local and runtime IDs.
3. Risky operations require explicit user confirmation (approvals/danger phrase/native action preview).
4. Persistence favors local durability (SQLite + atomic file writes + transcript checkpoints).
