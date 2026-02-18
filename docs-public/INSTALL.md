# Install / Build / Test

## Requirements

- macOS 13+ (SwiftPM platform minimum in `apps/CodexChatApp/Package.swift`).
- Xcode 26+ (or an equivalent Swift toolchain).
- `pnpm` (used only for workspace scripts).

## Build + Test

From the repo root:

```sh
pnpm -s run check
```

## Run In Xcode

Open the app package:

```sh
open apps/CodexChatApp/Package.swift
```

Select the `CodexChatApp` scheme and run.
