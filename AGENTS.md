# CodexChat Repository Instructions

## Product Direction
- Build CodexChat as a macOS-native, two-pane chat product.
- Keep the conversation canvas primary and avoid a persistent third pane in release one.
- Prioritize legibility, safety, and user-controlled local context.

## Source Of Truth
1. `AGENTS.md`
2. `README.md`
3. Private `docs/` (local planning memory, ignored by git)
4. Code reality

## Delivery Rules
- Work one epic at a time.
- Use small, atomic commits.
- Keep builds/tests green.
- Ship empty/loading/error states for user-facing surfaces.
- Accessibility basics are required, not optional.

## Prompt 1 Scope
- Foundation and project setup.
- Two-pane shell (`Projects + Threads` sidebar, chat canvas main).
- Design token system with injectable themes.
- Metadata persistence scaffolding.
- Hidden diagnostics screen.
- Minimal persistence and token tests.
