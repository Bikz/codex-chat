# Personal Actions (macOS)

CodexChat includes native personal actions so everyday users can ask for practical computer help without leaving chat.

## Scope (V1)

- Desktop cleanup (`desktop.cleanup`)
- Calendar lookup (`calendar.today`)
- Messages draft/send (`messages.send`)

## Adaptive Intent Routing

Automatic phrase-based composer interception is disabled by default.

CodexChat now prefers explicit user intent through normal chat and optional playbook prompts from Mods bar.

## Companion Skills (First-Party)

CodexChat ships tracked first-party skill templates for explicit personal-action workflows:

- `skills/first-party/macos-send-message/SKILL.md`
- `skills/first-party/macos-calendar-assistant/SKILL.md`
- `skills/first-party/macos-desktop-cleanup/SKILL.md`

These skills are designed to avoid accidental interception by:

- requiring clear intent/disambiguation when phrasing is ambiguous
- enforcing clarify -> preview -> confirm before sensitive operations
- requiring explicit confirmation for sends and filesystem changes

Typical usage patterns:

- select the skill from the composer skill picker, then prompt naturally
- use `personal-actions-playbook` mod actions, which insert prompts that call these skills when available

## Safety Contract

- Sensitive actions require preview artifacts before execution.
- Externally visible or file-changing actions require explicit confirmation.
- Execute calls are bound to the same run context as their preview.
- Permission decisions and outcomes are persisted locally.

## Action Behavior

### Desktop Cleanup

- Preview-only diff first (candidate files, target folders, operation summary).
- V1 performs move operations only (no permanent delete).
- Undo manifest is written and can restore the last cleanup.

### Calendar Today

- Read-only event listing for today (or supplied range window).
- Permission denial returns actionable guidance.

### Messages Send

- Draft preview shows recipient + body.
- Final send requires explicit user confirmation.
- Transcript action cards reflect sent/denied/failure outcomes.

## First-Party Packs

`mods/first-party` ships companion packs:

- `desktop-cleanup`
- `calendar-assistant`
- `messages-assistant`
- `personal-actions-playbook`

`personal-actions-playbook` inserts explicit Codex prompts (clarify -> preview -> confirm) instead of directly invoking native actions.

## Privacy

- Local-first storage only.
- No new remote analytics for personal action usage.
- Minimal persisted diagnostics (permissions + run outcomes).
