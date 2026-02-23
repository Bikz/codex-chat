# Team B UX Surfaces Built vs Next

Date: 2026-02-23

## 1) Already built UX capabilities (with evidence)
| Capability | What is built now | Evidence |
|---|---|---|
| Two-pane, conversation-first IA | Split layout keeps sidebar + canvas primary; onboarding collapses to detail-only when needed | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:13`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:183`, `/Users/bikram/Developer/CodexChat/AGENTS.md:7` |
| Auxiliary workflows without persistent third pane | Review, approvals, diagnostics, settings, mod review, plan runner all run as sheets/inline surfaces; shell is a drawer | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:94`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:55`, `/Users/bikram/Developer/CodexChat/AGENTS.md:11` |
| Strong canvas state UX | Canvas explicitly handles idle/loading/error/empty/success | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:583` |
| Project-level trust and safety UX | Trust toggles, sandbox/approval/network/web controls, danger phrase confirmation | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:179`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:325`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/DangerConfirmationSheet.swift:31` |
| Shell trust boundary UX | Untrusted projects require explicit warning before opening shell; warning persistence by project | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ShellState.swift:248`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/UntrustedShellWarningSheet.swift:17`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:2583` |
| Voice capture reliability UX | Permission/request/record/transcribe/fail flow with stale-session protection and auto-stop coverage | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+VoiceCapture.swift:102`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/VoiceCaptureStateTests.swift:108`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/VoiceCaptureStateTests.swift:151` |
| Keyboard and a11y baseline | Global shortcuts, composer shortcuts, labels/hints on key controls | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:33`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:173`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:357` |
| Theme/tokenized design system foundation | Shared design tokens, token card materials, glass flag wiring in root scene | `/Users/bikram/Developer/CodexChat/packages/CodexChatUI/Sources/CodexChatUI/DesignTokens.swift:4`, `/Users/bikram/Developer/CodexChat/packages/CodexChatUI/Sources/CodexChatUI/TokenCard.swift:16`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/CodexChatApp.swift:62` |
| Transcript rendering performance guardrails | Presentation row cache with bounded LRU and tests validating hit/invalidation behavior | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+TranscriptPresentationCache.swift:19`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/TranscriptPresentationTests.swift:473`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/TranscriptPresentationTests.swift:492` |

## 2) Next UX improvements (prioritized by impact and implementation risk)
Priority legend:
- P0 = contract/risk-critical.
- P1 = high impact polish and reliability.
- P2 = consistency/performance maintainability.

| Priority | Improvement | User impact | Implementation risk | Why now | Evidence |
|---|---|---|---|---|---|
| P0 | Normalize state rendering for sidebar general threads and review flows | High | Low | Team contract requires explicit empty/loading/error/success across user surfaces | `/Users/bikram/Developer/CodexChat/AGENTS.md:24`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:443`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ReviewChangesSheet.swift:12` |
| P0 | Fix accessibility focus visibility and missing labels in sidebar search | High | Low | Keyboard/focus is non-negotiable and currently regresses focus discoverability | `/Users/bikram/Developer/CodexChat/AGENTS.md:25`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:221`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:226` |
| P0 | Resolve stale doc-vs-code mismatches for personal actions/calendar | High | Low | Safety docs must match shipped behavior for trust and UX copy correctness | `/Users/bikram/Developer/CodexChat/docs-public/SECURITY_MODEL.md:67`, `/Users/bikram/Developer/CodexChat/packages/CodexComputerActions/Sources/CodexComputerActions/ComputerActionRegistry.swift:6`, `/Users/bikram/Developer/CodexChat/docs-public/PERSONAL_ACTIONS.md:13`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:13` |
| P1 | Remove silent error swallowing when loading expanded non-selected project threads | High | Low | Avoids confusing “empty” thread lists when a load actually failed | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:808` |
| P1 | Respect Reduce Motion in shared loading components | Medium | Low | Keeps motion behavior consistent with existing reduce-motion handling elsewhere | `/Users/bikram/Developer/CodexChat/packages/CodexChatUI/Sources/CodexChatUI/StateViews.swift:49`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:824` |
| P1 | Tighten shell keyboard/focus usability checks (split pane operations) | Medium | Medium | Shell is a high-power surface with trust boundaries and should be keyboard-complete | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ShellPaneChromeView.swift:42`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:2415` |
| P2 | Consolidate duplicated themed background logic into shared UI primitive | Medium | Medium | Reduces visual drift and makes light/dark + glass behavior consistent | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:214`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:53`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SettingsView.swift:959` |
| P2 | Consolidate duplicate relative-time and inline warning card UI patterns | Medium | Low | Reduces maintenance overhead and micro-inconsistency across surfaces | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:640`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:432`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:265`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ApprovalRequestSheet.swift:115` |

Assumption B1: P0 doc mismatches can be resolved either by docs updates or by behavior-gating, depending on product decision.

## 3) 30/60/90 day UX roadmap
### 0-30 days (stability + contract compliance)
- Ship explicit state completeness pass for Team B surfaces that are currently partial.
- Fix a11y focus visibility and missing control labels in sidebar search.
- Update stale docs for personal actions and calendar capability to match implementation truth.
- Add focused regression tests for sidebar state rendering and review-flow state presentation.

Exit criteria:
- No Team B-owned surface suppresses model `.loading` or `.failed` without user-visible feedback.
- Search field has visible focus indication and labeled clear action.
- Security/personal-actions docs align with current action registry and routing behavior.

### 31-60 days (workflow polish + reliability)
- Add explicit non-silent failure handling for expanded project thread fetches.
- Standardize approval/permission inline card shell styles and interactions.
- Add shell keyboard/focus flow tests for split, close, and session selection operations.
- Implement reduce-motion support in shared loading state primitives.

Exit criteria:
- Expanded project thread load failures are visible/recoverable.
- Inline warning and approval cards are style-consistent across canvas and sheets.
- Shell flow has deterministic keyboard/focus regression coverage.

### 61-90 days (consistency + maintainability)
- Extract shared themed background renderer across sidebar, detail, and settings surfaces.
- Extract shared relative-time formatter and reuse across sidebar/project settings.
- Extend journey scorecard to include visual QA snapshots for light/dark/glass parity.
- Final two-pane IA audit to verify no persistent third-pane regressions after polish.

Exit criteria:
- Background/token behavior is centralized and parity-tested for light/dark + glass modes.
- Duplicated utility logic replaced with shared primitives.
- Team B milestone M4 (two-pane compliance audit) is complete.

## 4) Dependencies on Runtime and Extensibility contracts
### Runtime Team (Workstream 1) dependencies
- Team B consumes runtime state contracts and should not bypass AppModel-published state.
  - `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:57`
- State UX quality depends on accurate failure/repair signaling as action cards and logs.
  - `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:59`
- Runtime mapping/recovery guarantees are prerequisites for stable approval and transcript UX.
  - `/Users/bikram/Developer/CodexChat/AGENTS.md:49`
  - `/Users/bikram/Developer/CodexChat/AGENTS.md:52`

### Extensibility Team (Workstream 3) dependencies
- Team B consumes mods/extensibility action descriptors and availability state.
  - `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:107`
- Mods bar UX correctness depends on schema constraints and supported action kinds.
  - `/Users/bikram/Developer/CodexChat/docs-public/MODS.md:42`
  - `/Users/bikram/Developer/CodexChat/docs-public/MODS.md:63`
- Native-action safety UX depends on extensibility/native action bridge metadata and permission semantics.
  - `/Users/bikram/Developer/CodexChat/docs-public/MODS.md:91`
  - `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:155`

Assumption B2: Contract ownership boundaries in `workstreams.md` remain active and unchanged during roadmap execution.

## Built-vs-next summary
- Built: Core two-pane UX, conversation-first rendering, and major safety/approval/shell/voice foundations are already in place.
- Next: Priority work is state-surface completeness, accessibility focus correctness, and removal of doc/behavior mismatches before broader visual polish.
