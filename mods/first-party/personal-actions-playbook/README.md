# Personal Actions Playbook Mod

First-party mod that inserts explicit Codex playbook prompts for personal actions.

## Why This Exists

- Avoid hidden phrase interception for sensitive actions.
- Keep workflow visible in chat.
- Require clarify -> preview -> confirm before externally visible or file-changing operations.

## Behavior

- Adds Mods bar actions that use `composer.insert`.
- Does not directly execute `native.action`.
- Lets users review/edit prompts before sending.
- Prompt playbooks reference companion first-party skills when available (`macos-send-message`, `macos-calendar-assistant`, `macos-desktop-cleanup`).

## Included Playbooks

- Guided message send protocol
- Read-only calendar review protocol
- Preview-first desktop cleanup protocol
