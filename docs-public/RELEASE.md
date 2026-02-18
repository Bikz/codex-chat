# Release Pipeline (Signed + Notarized + Stapled DMG)

CodexChat ships direct-download releases via a signed, notarized, stapled DMG attached to GitHub Releases.

## Architecture Support

- Current direct-download channel ships **Apple Silicon (`arm64`) only**.
- Release workflow and packaging script enforce `arm64` runners/hosts.

## Trigger

- Push a version tag: `v*` (example: `v0.2.0`).
- Workflow: `.github/workflows/release-dmg.yml`.

## Required GitHub Secrets

- `APPLE_DEVELOPER_ID_CERT_P12_BASE64`: base64-encoded Developer ID Application certificate (`.p12`).
- `APPLE_DEVELOPER_ID_CERT_PASSWORD`: password for the `.p12`.
- `APPLE_KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `APPLE_CODESIGN_IDENTITY`: Developer ID Application identity string (example: `Developer ID Application: Example, Inc. (TEAMID)`).
- `APPLE_NOTARY_KEY_ID`: App Store Connect API key ID.
- `APPLE_NOTARY_ISSUER_ID`: App Store Connect issuer ID.
- `APPLE_NOTARY_API_KEY_P8_BASE64`: base64-encoded contents of `AuthKey_<KEY_ID>.p8`.

## Build Script

- Script: `scripts/release/build-notarized-dmg.sh`
- Local invocation (after configuring signing + notary env vars):

```sh
VERSION=v0.2.0 ./scripts/release/build-notarized-dmg.sh
```

- Output artifacts:
  - `dist/CodexChat-<version>.dmg`
  - `dist/CodexChat-<version>.dmg.sha256`

The script validates notarization/stapling after upload:

- `xcrun stapler validate` for both `.app` and `.dmg`
- `spctl --assess --type execute` for app bundle
- `spctl --assess --type open` for DMG

## Local Non-Notarized Dry Run

```sh
SKIP_SIGNING=1 SKIP_NOTARIZATION=1 VERSION=local ./scripts/release/build-notarized-dmg.sh
```

This validates SwiftPM build + `.app`/DMG packaging without Apple credentials.
