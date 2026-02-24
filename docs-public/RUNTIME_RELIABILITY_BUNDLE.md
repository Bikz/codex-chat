# Runtime Reliability Diagnostics Bundle

CodexChat includes a one-command bundle flow so engineers can collect reliability evidence locally before merge.

## Command

```sh
make reliability-bundle
```

Outputs:

1. Bundle directory under `.artifacts/reliability/bundles/reliability-bundle-<timestamp>/`
2. Tar archive under `.artifacts/reliability/bundles/reliability-bundle-<timestamp>.tgz`

Bundle contents:

1. `doctor.txt`
2. `smoke.txt`
3. `policy-validate.txt`
4. Latest scorecard markdown/json (when present)
5. `metadata.env` (timestamp, git SHA, branch, policy file)

## Options

Skip scorecard regeneration:

```sh
RELIABILITY_BUNDLE_SKIP_SCORECARD=1 make reliability-bundle
```

## Why

1. Capture deterministic evidence for runtime/data reliability before push.
2. Make incident review and debugging reproducible across machines.
3. Provide a portable artifact for Team A reliability handoffs.
