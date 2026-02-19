# Messages Assistant Mod

First-party mod that prepares a message draft and then calls the native `messages.send` action.

## Behavior

- Uses a `Set Draft` prompt (`Recipient :: Message`) in Mods bar.
- Sends only through native preview + explicit confirmation.
- Records send outcomes through the computer-action run pipeline.
