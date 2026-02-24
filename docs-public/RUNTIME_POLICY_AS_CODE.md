# Runtime Policy as Code

CodexChat runtime safety defaults can be validated from a tracked JSON policy document.

Default policy file:

`config/runtime-policy/default-policy.json`

## Why

1. Make dangerous-mode defaults explicit and reviewable.
2. Keep approval/sandbox expectations legible in code review.
3. Enforce local reliability gates before push.

## Validate Policy

```sh
cd apps/CodexChatApp
swift run CodexChatCLI policy validate \
  --file ../../config/runtime-policy/default-policy.json
```

Or rely on default resolution:

```sh
cd apps/CodexChatApp
swift run CodexChatCLI policy validate
```

`make reliability-local` also runs policy validation.

## Policy Schema (v1)

Required fields:

1. `version`
2. `defaultApprovalPolicy` (`untrusted`, `on-request`, `never`)
3. `defaultSandboxMode` (`read-only`, `workspace-write`, `danger-full-access`)
4. `allowNetworkAccess` (boolean)
5. `allowWebSearch` (boolean)
6. `allowDangerFullAccess` (boolean)
7. `allowNeverApproval` (boolean)

Validation rules:

1. `defaultApprovalPolicy=never` requires `allowNeverApproval=true`.
2. `defaultSandboxMode=danger-full-access` requires `allowDangerFullAccess=true`.
