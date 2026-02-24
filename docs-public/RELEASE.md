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
- CI/release workflow enforces `arm64` runner/host.

## Trigger

- Tag push: `v*` (example `v0.2.0`)
- Workflow: `.github/workflows/release-dmg.yml`

## Auto-Increment Version + Build

- Version auto-increment helper (patch bump, starting at `v0.0.1` when no tags exist):

```sh
make release-next-version
```

- Create + push next release tag (triggers GitHub release workflow):

```sh
make release-tag-next
```

- Build number is already auto-incremented in CI via `GITHUB_RUN_NUMBER`.

## Required Secrets

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
