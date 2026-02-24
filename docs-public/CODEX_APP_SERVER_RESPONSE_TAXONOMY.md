# Codex App-Server Response Taxonomy

Last updated: 2026-02-24

## Why this exists

CodexChat currently renders many runtime updates through generic action cards and heuristic status labels. This document is the canonical inventory of response types coming from `codex app-server`, how we decode them, and how they are currently rendered. It is meant to drive per-state UX treatment improvements.

## Scope

This covers runtime traffic that reaches CodexChat through `CodexKit` and `CodexChatApp`:

1. JSON-RPC envelope classes on the wire.
2. Request/response methods initiated by CodexChat.
3. Server requests and notifications initiated by app-server.
4. Synthetic runtime events generated locally when transport/framing fails.
5. Current UI treatment and known UX gaps.

## Layer 1: Wire-level message categories

`JSONRPCMessageEnvelope` identifies three categories:

- `response`: `id != nil` and (`result` or `error`) present.
- `notification`: `id == nil` and `method != nil`.
- `server request`: `id != nil`, `method != nil`, no `result`/`error`.

Reference: `packages/CodexKit/Sources/CodexKit/JSONRPC.swift`

## Layer 2: CodexChat-initiated RPC responses

These are request methods CodexChat sends and expects results/errors for.

| Method | Expected success payload | Consumed in |
| --- | --- | --- |
| `initialize` | `result.capabilities` (optional `turnSteer`, `followUpSuggestions`) | `performHandshake` + `decodeCapabilities` |
| `thread/start` | `result.thread.id` | `startThread` |
| `turn/start` | `result.turn.id` | `startTurn` |
| `turn/steer` | any ack payload (currently ignored) | `steerTurn` |
| `account/read` | `result.requiresOpenaiAuth`, optional `result.account` | `readAccount` |
| `account/login/start` | chatgpt: `result.authUrl`, optional `result.loginId`; apiKey: ack only | `startChatGPTLogin`, `startAPIKeyLogin` |
| `account/login/cancel` | ack only | `cancelChatGPTLogin` |
| `account/logout` | ack only | `logoutAccount` |
| `model/list` | `result.data[]`, optional `result.nextCursor` | `listModels`, `decodeModelList` |

Reference: `packages/CodexKit/Sources/CodexKit/CodexRuntime+PublicAPI.swift`, `packages/CodexKit/Sources/CodexKit/CodexRuntime+RPC.swift`

## Layer 3: App-server requests (server -> client)

CodexChat currently handles one server-request family:

| Pattern | Decoded as | Notes |
| --- | --- | --- |
| `*/requestApproval` | `CodexRuntimeEvent.approvalRequested(RuntimeApprovalRequest)` | `kind` inferred from method (`commandExecution`, `fileChange`, else `unknown`) |

Approval payload fields currently parsed:

- `threadId`, `turnId`, `itemId`
- `reason`, `risk`, `cwd`
- `command` (array or string)
- `changes[]` (`path`, `kind`, `diff`)

References:

- `packages/CodexKit/Sources/CodexKit/CodexRuntime+RPC.swift`
- `packages/CodexKit/Sources/CodexKit/CodexRuntime+Params.swift`

## Layer 4: App-server notifications -> `CodexRuntimeEvent`

All notification decoding lives in `AppServerEventDecoder.decodeAll`.

| Notification method | Decoded event(s) | Core payload fields used |
| --- | --- | --- |
| `thread/started` | `.threadStarted` | `thread.id` |
| `turn/started` | `.turnStarted` | `threadId`, `turn.id` |
| `item/agentMessage/delta` | `.assistantMessageDelta(RuntimeAssistantMessageDelta)` | `threadId`, `turnId`, `itemId`, `delta`, optional `channel`, optional `stage` |
| `item/commandExecution/outputDelta` | `.commandOutputDelta` | `threadId`, `turnId`, `itemId`, `delta` |
| `turn/followUpsSuggested` | `.followUpSuggestions` | `threadId`, `turnId`, `suggestions[]` |
| `item/started` | `.action` (+ `.fileChangesUpdated` if `item.type == fileChange`) | `item.id`, `item.type`, `item.status`, `item.changes[]`, optional worker trace |
| `item/completed` | `.action` (+ `.fileChangesUpdated` if `item.type == fileChange`) | same as above |
| `turn/completed` | `.turnCompleted` | `threadId`, `turn.id`, `turn.status`, `turn.error.message` |
| `account/updated` | `.accountUpdated` | `authMode` |
| `account/login/completed` | `.accountLoginCompleted` | `loginId`, `success`, `error` |

Unknown notification methods are ignored.

Reference: `packages/CodexKit/Sources/CodexKit/AppServerEventDecoder.swift`

### Assistant message channel metadata

`RuntimeAssistantMessageDelta` now carries:

- `channel` (`final`, `progress`, `system`, `unknown`)
- optional `stage` (for phase labels like `planning`, `mapping`, etc.)

Decoder behavior:

- missing channel defaults to `final`
- unknown channel strings decode to `unknown`
- when explicit channel is absent, decoder may infer `progress/system` from `item.type` hints

## Layer 5: Synthetic runtime events generated locally

These do not come directly from app-server notifications, but appear in transcript/log UX as runtime actions:

| Source | Synthetic method | Trigger |
| --- | --- | --- |
| stdout framing/JSON decode failure | `runtime/stdout/decode_error` | JSONL or decode failure while parsing stdout |
| stderr line pump | `runtime/stderr` | any stderr line emitted by process |
| process termination | `runtime/terminated` | app-server process exits unexpectedly |
| approval reconciliation (app logic) | `approval/reset` | stale approvals cleared after reconnect/termination |
| local turn-start failure (app logic) | `turn/start/error` | `turn/start` dispatch fails |
| local mod review guard (app logic) | `mods/reviewRequired` | mod-file edits require explicit review |

References:

- `packages/CodexKit/Sources/CodexKit/CodexRuntime+Process.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Runtime.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimePersistence.swift`

## Layer 6: `item.type` taxonomy inside action events

`item/started` and `item/completed` are generic; subtype comes from `item.type` (string).

Observed in fixtures/tests:

- `reasoning`
- `webSearch`
- `commandExecution`
- `fileChange`
- `toolCall`

The decoder is open-ended: any `item.type` string is accepted and shown as `Started <type>` / `Completed <type>`.

References:

- `packages/CodexKit/Sources/CodexKit/AppServerEventDecoder.swift`
- `packages/CodexKit/Tests/CodexKitTests/CodexKitTests.swift`
- `apps/CodexChatApp/Tests/CodexChatAppTests/LiveActivityTraceFormatterTests.swift`

## Current UI treatment by response type

### Conversation transcript rows

`TranscriptEntry` is projected into:

- `message` row (user/assistant text)
- `action` row (inline notice in compact modes, full card in detailed mode)
- `liveActivity` row (active turn only)
- `turnSummary` row (compacted history)

Progress deltas (`channel = progress/system`) now render as inline system-style transcript messages in the active turn, separate from the final assistant answer stream.

References:

- `apps/CodexChatApp/Sources/CodexChatApp/TranscriptPresentation.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift`

### Status labels in active turn

Current live status is heuristic string matching over action method/title/detail:

- `Searching`
- `Thinking`
- `Running`
- `Editing`
- `Reading`
- `Waiting`
- `Troubleshooting`
- fallback `Working`

Reference: `apps/CodexChatApp/Sources/CodexChatApp/LiveActivityTraceFormatter.swift`

### Approval UX

- `approvalRequested` shows inline approval UI replacing composer.
- Decisions: `Approve Once`, `Approve for Session`, `Decline`.
- Separate inline variants exist for runtime approvals, computer-action previews, and permission recovery notices.

References:

- `apps/CodexChatApp/Sources/CodexChatApp/ApprovalRequestSheet.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+Approvals.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift`

### Shell/command output UX

- `item/commandExecution/outputDelta` is appended to thread logs (`threadLogsByThreadID`).
- Bottom drawer currently shows local interactive shell workspace (`ShellWorkspaceDrawer`), not app-server command-output stream.
- `ThreadLogsDrawer` exists but is not currently wired into `ChatsCanvasView`.

References:

- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ShellWorkspaceDrawer.swift`

### Progress timeline UX

- Progress updates are first-class transcript content (flat, inline, no user-style bubble).
- Final assistant text remains isolated to `channel = final` (or `unknown`) and continues to drive completion/title/memory behavior.
- Backward-compatible fallback can synthesize brief progress notes from active action milestones when explicit progress deltas are absent.

References:

- `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ConversationUpdateScheduler.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/TranscriptPresentation.swift`
- `apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift`

### Extension/Mods bar (user called out as MCP/MFP-like surface)

- Not a direct app-server event type.
- Rendered as adjacent UI rail/panel (`conversationWithModsBar`) driven by extension state.
- Runtime action cards still appear in transcript; extension output appears in mods bar surface.

Reference: `apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift`

## Key UX gaps discovered

1. Status treatment is heuristic, not typed.
- We infer state from strings (`search`, `reasoning`, `command`, etc.), so new tool names can be mislabeled.

2. Command output stream is decoupled from transcript context.
- Runtime command deltas are logged, but chat does not show a per-command inline output preview by default.

3. `item.type` is flattened into generic action titles.
- `toolCall`, `webSearch`, `reasoning`, `fileChange` all share the same card mechanics with minimal semantic differentiation.

4. Unknown notifications are silently dropped.
- Good for compatibility, but there is no observability for newly introduced server methods.

5. Follow-up suggestion events are operationally handled, but not represented as transcript milestones.
- Suggestions go into queue/status text, not as explicit turn-level response artifacts.

## Recommended typed UX state model

Introduce a first-class UI state enum derived from event + payload, before presentation:

- `assistant_streaming`
- `reasoning_active`
- `web_search_active`
- `file_read_active`
- `tool_call_active`
- `command_exec_active`
- `command_output_streaming`
- `file_change_preview`
- `approval_required`
- `approval_resolved`
- `warning_stderr`
- `error_stderr`
- `runtime_terminated`
- `turn_completed_success`
- `turn_completed_failure`
- `account_state_changed`
- `login_completed`

Then map each to distinct rendering primitives (iconography, tint, verbosity, collapse behavior, and whether output appears inline vs in drawer).

## Suggested near-term UX changes

1. Inline command preview card for `command_output_streaming`.
- Show the latest N lines for the active command directly in `liveActivity`, with "Open full logs" affordance.

2. Use `item.type`-driven icons and labels.
- Example: `reasoning`, `webSearch`, `toolCall`, `fileChange`, `commandExecution` each get dedicated visual treatment.

## Implemented in CodexChat (2026-02-24)

The following UX changes are now shipped in `CodexChatApp`:

1. Typed runtime state classification now drives transcript and live activity labeling.
- `RuntimeVisualStateClassifier` maps runtime actions to dedicated visual states (`reasoning`, `webSearch`, `toolCall`, `commandExecution`, approvals, stderr warning/error, completion/failure, etc.).
- Action rows use state-specific iconography + tone instead of generic method heuristics.
- Live activity status labels now derive from typed state classification.

2. Inline terminal preview for active command runs is rendered directly in chat.
- Active live-activity rows include a scrollable monospaced output surface fed from thread runtime logs.
- Large command output streams remain scrollable within the chat timeline.

3. Assistant file references are now first-class clickable links.
- Backticked file references in assistant markdown are linkified into `codexchat-file://` links.
- File links resolve safely against the selected project root (`ProjectPathSafety`) and open locally.

4. Assistant stream now supports explicit progress channels with inline timeline treatment.
- `item/agentMessage/delta` decoding now supports optional `channel` + `stage` metadata.
- `progress/system` channel deltas render as inline progress notes during active turns.
- `final/unknown` channel deltas continue to render as the canonical assistant answer stream.
- Runtime action milestones can synthesize fallback progress notes while active when explicit progress deltas are not emitted.

Primary implementation references:
- `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/RuntimeVisualState.swift`
- `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/TranscriptPresentation.swift`
- `/Users/bikram/Developer/CodexChat/packages/CodexKit/Sources/CodexKit/RuntimeModels.swift`
- `/Users/bikram/Developer/CodexChat/packages/CodexKit/Sources/CodexKit/AppServerEventDecoder.swift`
- `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift`
- `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/MarkdownMessageView.swift`

3. Replace heuristic status labeling with typed status.
- Keep heuristic fallback only for unknown/new item types.

4. Add lightweight "unknown runtime event" diagnostics breadcrumb.
- Do not surface noisy UI to end users; record in diagnostics/perf logs so protocol drift is visible.

5. Render follow-up suggestion receipt as compact transcript milestone.
- Example: "Suggested 2 follow-ups" row with quick insert actions.

## Implementation hotspots for the redesign

- Runtime event decode boundary: `packages/CodexKit/Sources/CodexKit/AppServerEventDecoder.swift`
- Runtime event handling: `apps/CodexChatApp/Sources/CodexChatApp/AppModel+RuntimeEvents.swift`
- Presentation compaction/classification: `apps/CodexChatApp/Sources/CodexChatApp/TranscriptPresentation.swift`
- Active-turn status formatter: `apps/CodexChatApp/Sources/CodexChatApp/LiveActivityTraceFormatter.swift`
- Row components: `apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift`
- Canvas composition and drawers: `apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift`
