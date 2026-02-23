# Team B UX Surfaces Research

Date: 2026-02-23

## Scope and method
This research covers Team B's owned UX scope and validates journey quality against product contracts.

Evidence sources:
- Product and architecture contracts: `/Users/bikram/Developer/CodexChat/AGENTS.md:7`, `/Users/bikram/Developer/CodexChat/README.md:117`, `/Users/bikram/Developer/CodexChat/docs-public/ARCHITECTURE_CONTRACT.md:5`
- Planning inventories/journeys/workstreams: `/Users/bikram/Developer/CodexChat/docs-public/planning/feature-inventory.md:16`, `/Users/bikram/Developer/CodexChat/docs-public/planning/user-journeys.md:7`, `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:70`
- Primary UI code in Team B scope: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:13`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:100`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:15`
- UI package and tests: `/Users/bikram/Developer/CodexChat/packages/CodexChatUI/Sources/CodexChatUI/StateViews.swift:3`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/SidebarSelectionTests.swift:70`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:2415`

Assumption A1: Scores below rate current implementation quality from code+tests, not visual QA from full manual runs.
Assumption A2: "Journey completeness" means explicit empty/loading/error/success handling in the rendered surface, not only in model state enums.

## 1) UX architecture map and interaction model
The app currently adheres to two-pane, conversation-first IA with auxiliary workflows implemented as sheets, inline cards, and a bottom drawer.

Contract evidence:
- Two-pane and no persistent third pane: `/Users/bikram/Developer/CodexChat/AGENTS.md:7`, `/Users/bikram/Developer/CodexChat/AGENTS.md:10`, `/Users/bikram/Developer/CodexChat/README.md:118`
- Conversation-first with auxiliary sheets/drawers: `/Users/bikram/Developer/CodexChat/AGENTS.md:11`

Implementation map:

| Surface | Interaction model | Evidence |
|---|---|---|
| Sidebar | Project/thread selection, search, project controls, account/settings entry | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:100` |
| Conversation canvas | Runtime-aware transcript + composer + inline approval/permission banners | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:26`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:30` |
| Bottom drawer (shell) | Optional shell workspace attached under composer/canvas | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:55` |
| Sheets (aux workflows) | Diagnostics, project settings, review changes, mod review, approvals, untrusted shell warning, plan runner | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:94`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:127`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:131` |
| Onboarding | Dedicated detail-only mode until runtime/account readiness | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:169`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:183` |
| Settings | Split settings navigation + detail sections for account/theme/runtime/safety/storage | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SettingsView.swift:39`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SettingsView.swift:183` |
| Diagnostics | Runtime/pool/perf/log status window with refresh loop | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/DiagnosticsView.swift:44`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/DiagnosticsView.swift:168` |
| Review flows | Generic review sheet + mandatory mod review + approval sheet content | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ReviewChangesSheet.swift:4`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ModChangesReviewSheet.swift:6`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ApprovalRequestSheet.swift:5` |
| Voice capture | Composer mic, permission flow, idle/request/record/transcribe/fail states | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:122`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+VoiceCapture.swift:31` |

## 2) Journey quality scorecard by surface
Scoring rubric:
- 5 = robust and consistent.
- 4 = good, minor gaps.
- 3 = usable but uneven.
- 2 = notable reliability/UX debt.
- 1 = high-risk surface.

| Surface | Score | Current quality | Evidence | Main gaps |
|---|---:|---|---|---|
| Sidebar | 3 | Strong controls and a11y labels; partial state rendering | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:357`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:443` | General-thread idle/loading/failed are suppressed to `EmptyView` |
| Conversation canvas | 4 | Good state branching and trust-aware transcript flow | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:583`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift:43` | Shell divider layering and mod-bar divider can add extra visual separators |
| Onboarding | 4 | Clear account/runtime readiness path with install/restart options | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatSetupView.swift:93`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:1924` | No explicit "retry startup" CTA on the onboarding cards themselves |
| Settings | 4 | Broad coverage and strong safety controls | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SettingsView.swift:85`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SettingsView.swift:829` | Section-level loading/error is mostly status-text based, not full state surfaces |
| Project settings | 4 | Good archived chats state handling and danger confirmation | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:375`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:93` | Minor duplication in relative-time logic and card patterns |
| Shell workspace | 4 | Trust-gated open path; per-project session model; strong tests | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ShellState.swift:248`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:2583` | Keyboard/focus traversal in split panes not explicitly tested |
| Review flows | 3 | Core accept/revert actions exist | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ReviewChangesSheet.swift:43`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ModChangesReviewSheet.swift:65` | Missing explicit loading/error/success wrappers in sheets |
| Voice capture | 4 | Strong concurrency/race handling and comprehensive tests | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+VoiceCapture.swift:102`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/VoiceCaptureStateTests.swift:151` | Runtime-disabled message UX exists but could be more proactive in composer |
| Diagnostics | 4 | Good empty states and live perf refresh | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/DiagnosticsView.swift:90`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/DiagnosticsView.swift:115` | Export failure path appears status-based outside this view |

## 3) State coverage matrix (empty/loading/error/success)
Contract baseline: `/Users/bikram/Developer/CodexChat/AGENTS.md:24` and `/Users/bikram/Developer/CodexChat/docs-public/planning/user-journeys.md:7`.

Legend:
- Full = all four states visible in surface UI.
- Partial = model has states, UI suppresses or merges one/more states.
- Missing = no explicit handling in surface code.

| Surface | Empty | Loading | Error | Success | Coverage | Evidence |
|---|---|---|---|---|---|---|
| Conversation canvas | Yes | Yes | Yes | Yes | Full | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:584`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:592`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:596`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:606` |
| Sidebar search surface | Yes | Yes | Yes | Yes | Full | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:664` |
| Sidebar general threads | Implicit | No | No | Yes | Partial | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:443`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel.swift:521` |
| Expanded non-selected project thread list | Yes | Yes | No (silent) | Yes | Partial | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:423`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:808` |
| Project settings archived chats | Yes | Yes | Yes | Yes | Full | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:379`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:382`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:389` |
| Shell workspace drawer | Yes | Yes (session creation path) | Yes | Yes | Full | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ShellWorkspaceDrawer.swift:30`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ShellWorkspaceDrawer.swift:100`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ShellWorkspaceDrawer.swift:125` |
| Review changes sheet | Yes | No | No | Yes | Partial | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ReviewChangesSheet.swift:12` |
| Mod review sheet | Partial ("No diff available") | No | No | Yes | Partial | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ModChangesReviewSheet.swift:43`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ModChangesReviewSheet.swift:49` |
| Approval sheet | No explicit empty/loading/error wrapper | No | Status text only | Yes | Partial | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ApprovalRequestSheet.swift:252` |
| Diagnostics | Yes | Yes | Partial | Yes | Partial | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/DiagnosticsView.swift:90`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/DiagnosticsView.swift:168` |

Assumption A3: "Loading" for shell/diagnostics is represented by session creation/perf refresh loops rather than explicit load state enums.

## 4) Accessibility findings and gaps
### Strengths
- Sidebar and toolbar controls have explicit labels/hints and keyboard shortcuts.
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:31`
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:33`
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:357`
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:497`
- Composer controls include focused text input, labels, and send/voice shortcuts.
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:98`
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:149`
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:173`
- Reduced-motion handling exists in transcript activity and sidebar spinner.
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ConversationComponents.swift:254`
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:824`

### Gaps
- Search field disables focus effect, reducing keyboard focus visibility in a contract-critical surface.
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:221`
  - Contract: `/Users/bikram/Developer/CodexChat/AGENTS.md:25`
- Search clear button has no explicit accessibility label/hint.
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:226`
- Shared loading state animation ignores reduce-motion and always pulses.
  - `/Users/bikram/Developer/CodexChat/packages/CodexChatUI/Sources/CodexChatUI/StateViews.swift:49`
- Shell pane keyboard operation is inferred from mouse/tap callbacks; no explicit keyboard shortcut coverage found in shell-specific tests.
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ShellPaneChromeView.swift:42`
  - `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Tests/CodexChatAppTests/CodexChatAppTests.swift:2415`

Assumption A4: Some platform-level accessibility behavior may come from SwiftUI defaults not visible in unit tests.

## 5) Duplicate UI logic and refactor opportunities
| Opportunity | Duplicate evidence | Recommendation |
|---|---|---|
| Themed gradient background composition | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ContentView.swift:214`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:53`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SettingsView.swift:959` | Create a shared `ThemedSurfaceBackground` in `CodexChatUI` to remove divergence in opacity/gradient behavior. |
| Relative time formatter | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:640`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ProjectSettingsSheet.swift:432` | Move to shared `RelativeTimeFormatter` helper (single source for thresholds). |
| Inline warning/approval card shells | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ChatsCanvasView.swift:265`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ApprovalRequestSheet.swift:115`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ApprovalRequestSheet.swift:58` | Introduce a unified `InlineActionNoticeCard` component for warning icon, body copy, and CTA row spacing. |
| Panel surface color/stroke conventions in shell | `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ShellWorkspaceDrawer.swift:134`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ShellPaneChromeView.swift:86` | Fold shell panel visuals into tokenized `tokenCard` or `SurfaceStyle` helpers. |

## 6) Stale docs audit (implementation vs docs)
| Severity | Stale statement | Evidence in docs | Evidence in implementation | Assessment |
|---|---|---|---|---|
| High | Calendar is "read-only in v1" | `/Users/bikram/Developer/CodexChat/docs-public/SECURITY_MODEL.md:67` | Calendar create/update/delete are registered providers: `/Users/bikram/Developer/CodexChat/packages/CodexComputerActions/Sources/CodexComputerActions/ComputerActionRegistry.swift:6` | Doc and implementation diverge; update security and personal-actions docs to match shipped capabilities or gate actions. |
| High | Automatic phrase interception disabled by default | `/Users/bikram/Developer/CodexChat/docs-public/PERSONAL_ACTIONS.md:13` | Composer path calls adaptive intent routing: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+FollowUps.swift:13`; routing enables desktop/calendar/reminders/messages intents: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+AdaptiveIntent.swift:44`; default native-actions flag is true: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/AppModel+ComputerActions.swift:880` | Behavior appears on-by-default when native actions are enabled; docs need clarification or code needs explicit opt-in setting. |
| Medium | Team B owns final empty/loading/error/success semantics | `/Users/bikram/Developer/CodexChat/docs-public/planning/workstreams.md:108` | Multiple Team B surfaces still suppress or collapse states: `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/SidebarView.swift:443`, `/Users/bikram/Developer/CodexChat/apps/CodexChatApp/Sources/CodexChatApp/ReviewChangesSheet.swift:12` | Planning target is not fully realized yet; keep as active backlog item, not completed capability. |

## Key takeaways
- The two-pane, conversation-first architecture is implemented correctly and consistently.
- State completeness is strongest in canvas/search/project-settings, but weaker in sidebar general threads and review flows.
- Accessibility foundations are solid, but focus visibility and reduced-motion consistency have concrete gaps.
- Docs have high-signal mismatches around personal actions and calendar capability scope that should be corrected before wider UX polish work.
