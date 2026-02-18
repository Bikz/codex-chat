# CodexChat Public Docs

This folder is tracked in git.

Private planning and internal memory docs live in `docs/` and are intentionally ignored by git.

## Contents

- `INSTALL.md`: build and test locally.
- `SECURITY_MODEL.md`: safety + permissions model (high level).
- `MODS.md`: UI mod format, directories, and precedence.
- `MODS_SHARING.md`: how to create and share custom Skills and Mods.
- `CONTRIBUTING.md`: contribution workflow and repo conventions.

## Runtime Follow-Up Features

- Composer policy: Enter sends immediately when idle; while a turn is in progress, messages are queued as follow-ups.
- Queue scope: follow-ups are persisted per thread and survive app restarts.
- Dispatch policy: Auto-mode follow-ups drain in FIFO order when runtime dispatch gates are open; failures pause at the head in failed state.
- Steer support: when runtime initialize capabilities include `turnSteer`, queued items can be injected in-flight via `turn/steer`; otherwise client falls back to "queue next."
- Suggestion support: when capabilities include `followUpSuggestions`, client accepts `turn/followUpsSuggested` notifications and stores suggestions as manual follow-ups.

## Root-Level Meta Files

GitHub also reads these from the repo root:

- `CONTRIBUTING.md` (pointer to this folder)
- `CODE_OF_CONDUCT.md`
- `SECURITY.md`
- `LICENSE`
