# ADR: Mods Bar Actions + GitHub Subdirectory Install

## Status

Accepted.

## Context

CodexChat prioritized a GitHub/local-only extension channel for this cycle while shipping feature-complete exemplar mods (Personal Notes, Thread Summary, Prompt Book). Two practical gaps remained:

- install from GitHub monorepos where a mod lives in a repository subdirectory
- interactive Mods bar workflows that can trigger extension actions (for example add/edit notes, one-click prompt send)

## Decision

1. Keep remote install channel restricted to GitHub, plus local folder installs.
2. Add GitHub `tree`/subdirectory source handling in installer:
   - accept URLs like `https://github.com/org/repo/tree/main/path/to/mod`
   - clone repo, then resolve package root inside the requested subdirectory
3. Add typed Mods bar actions in extension worker output:
   - `emitEvent`
   - `promptThenEmitEvent`
   - `composer.insert`
   - `composer.insertAndSend`
4. Add new runtime event `modsBar.action` for UI-triggered extension actions.
5. Add Mods bar output scopes:
   - `thread` (default)
   - `global` (cross-chat/project surface state)

## Consequences

Positive:

- One-click install works for real-world monorepo layouts.
- Feature mods can provide first-class in-UI actions without host special-casing.
- Prompt Book can be global while preserving two-pane constraints.

Tradeoffs:

- Additional runtime/action handling complexity.
- New action surface requires strict payload validation and safe defaults.

## Follow-up

1. Add signed metadata/integrity policy for hosted catalog work (future cycle).
2. Expand action primitives only as needed; keep strongly typed behavior.
3. Keep diagnostics non-sensitive for action dispatch/install failures.
