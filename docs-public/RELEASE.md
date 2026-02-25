# Release Pipeline (Signed + Notarized DMG)

CodexChat ships direct-download releases as signed, notarized, stapled DMG artifacts attached to GitHub Releases.

## Canonical Source

Release app bundles are built from host archive output only:

- Project: `apps/CodexChatHost/CodexChatHost.xcodeproj`
- Scheme: `CodexChatHost`
- Script: `scripts/release/build-notarized-dmg.sh`

SwiftPM GUI binaries are not release inputs.

## Architecture Support

- Current distribution: Apple Silicon (`arm64`) only.
- Local release host is enforced as `arm64` by `scripts/release/build-notarized-dmg.sh`.

## Trigger

- Canonical trigger: run `make release-prod` locally.
- Optional hosted path: manual `workflow_dispatch` on `.github/workflows/release-dmg.yml`.

## Auto-Increment Version + Build

- Preferred production release command (local-first):

```sh
make release-prod
```

Optional controls:

- `VERSION=v0.0.7 make release-prod` (force a specific version)
- `USE_GITHUB_RELEASE_WORKFLOW=1 make release-prod` (opt into manual hosted workflow mode)
- `RELEASE_TIMEOUT_MINUTES=30 make release-prod` (only applies when hosted workflow mode is enabled)
- `ENABLE_LOCAL_FALLBACK=0 make release-prod` (only applies when hosted workflow mode is enabled)

`release-prod` behavior:

- Idempotent retries: re-running a version will reuse existing tag/release and only upload missing/replaceable assets.
- Local-first: creates/uses release tag, runs signed/notarized local build, and uploads assets to GitHub release.
- Hosted workflow mode (`USE_GITHUB_RELEASE_WORKFLOW=1`): waits on `.github/workflows/release-dmg.yml`, then falls back locally if enabled.
- Hosted workflow diagnostics: prints failing GitHub Actions run details and failed logs before local fallback.
- Post-release verification: asserts release is not draft/prerelease and contains both required assets.

- Version auto-increment helper (patch bump, starting at `v0.0.1` when no tags exist):

```sh
make release-next-version
```

- Create + push next release tag:

```sh
make release-tag-next
```

- Local builds default `BUILD_NUMBER=1` unless explicitly provided.

## Required Local Credentials

- Local keychain contains your Apple Developer ID signing identity.
- Environment variables for local signing/notarization:
  - `CODESIGN_IDENTITY`
  - `NOTARY_KEY_ID`
  - `NOTARY_ISSUER_ID`
  - `NOTARY_KEY_FILE` (path to local `AuthKey_<KEY_ID>.p8`)

## Optional Hosted Workflow Secrets

Only required when running `.github/workflows/release-dmg.yml` manually:

- `APPLE_DEVELOPER_ID_CERT_P12_BASE64`
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_CODESIGN_IDENTITY`
- `APPLE_NOTARY_KEY_ID`
- `APPLE_NOTARY_ISSUER_ID`
- `APPLE_NOTARY_API_KEY_P8_BASE64`

## Local Invocation

```sh
VERSION=v0.0.1 ./scripts/release/build-notarized-dmg.sh
```

Default app category for release artifacts is `public.app-category.developer-tools` (override with `APP_CATEGORY_TYPE` if needed).

Artifacts:

- `dist/CodexChat-<version>.dmg`
- `dist/CodexChat-<version>.dmg.sha256`

DMG contents:

- `CodexChat.app`
- `Applications` shortcut (drag-and-drop install UX)

## Dry Run (No Signing/Notarization)

```sh
SKIP_SIGNING=1 SKIP_NOTARIZATION=1 VERSION=local ./scripts/release/build-notarized-dmg.sh
```

## Guardrails

Release and CI guardrails:

- `scripts/check-host-app-metadata.sh`
- `scripts/verify-build-settings-parity.sh`
- `scripts/verify-app-bundle.sh <path-to-app>`

Validation checks include bundle ID, versions, minimum OS, icon assets, code signature, hardened runtime, and stapling checks where applicable.

## Icon Sources

- `apps/CodexChatHost/CodexChatHost/Resources/AppIcon.icns`
- `apps/CodexChatHost/CodexChatHost/Assets.xcassets/AppIcon.appiconset`

## Future Improvements Backlog

- Add automatic release notes/changelog generation.
- Add provenance/SBOM attestation for release artifacts.
- Keep release toolchain deterministic with explicit Xcode/runner validation policy.
- Enforce stricter branch/tag protections on release paths.
- Add post-release clean-machine install smoke verification.
