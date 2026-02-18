#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST_PROJECT="${HOST_PROJECT:-$ROOT/apps/CodexChatHost/CodexChatHost.xcodeproj}"
HOST_SCHEME="${HOST_SCHEME:-CodexChatHost}"
PACKAGE_SWIFT="$ROOT/apps/CodexChatApp/Package.swift"
HOST_INFO_PLIST="$ROOT/apps/CodexChatHost/CodexChatHost/Info.plist"
RELEASE_SCRIPT="$ROOT/scripts/release/build-notarized-dmg.sh"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -f "$PACKAGE_SWIFT" ]] || fail "missing $PACKAGE_SWIFT"
[[ -f "$HOST_INFO_PLIST" ]] || fail "missing $HOST_INFO_PLIST"
[[ -f "$RELEASE_SCRIPT" ]] || fail "missing $RELEASE_SCRIPT"

build_settings="$(xcodebuild \
  -project "$HOST_PROJECT" \
  -scheme "$HOST_SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -showBuildSettings)"

setting() {
  local key="$1"
  local value
  value="$(awk -F ' = ' -v key="$key" '$1 ~ "^[[:space:]]*" key "$" { print $2; exit }' <<<"$build_settings")"
  [[ -n "$value" ]] || fail "missing build setting $key from host target"
  echo "$value"
}

host_bundle_id="$(setting PRODUCT_BUNDLE_IDENTIFIER)"
host_min_os="$(setting MACOSX_DEPLOYMENT_TARGET)"
host_marketing_version="$(setting MARKETING_VERSION)"
host_build_number="$(setting CURRENT_PROJECT_VERSION)"

plist_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$HOST_INFO_PLIST" 2>/dev/null || true)
plist_min_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$HOST_INFO_PLIST" 2>/dev/null || true)
plist_marketing_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$HOST_INFO_PLIST" 2>/dev/null || true)
plist_build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$HOST_INFO_PLIST" 2>/dev/null || true)

package_min_major="$(perl -nle 'if (/platforms:\s*\[\.macOS\(\.v(\d+)\)\]/) { print $1; exit }' "$PACKAGE_SWIFT")"
[[ -n "$package_min_major" ]] || fail "unable to read macOS deployment target from $PACKAGE_SWIFT"
package_min_os="${package_min_major}.0"

release_bundle_id="$(perl -nle 'if (/^APP_BUNDLE_ID=.*:-([^\}]+)\}/) { print $1; exit }' "$RELEASE_SCRIPT")"
[[ -n "$release_bundle_id" ]] || fail "unable to read APP_BUNDLE_ID default from $RELEASE_SCRIPT"

[[ "$host_bundle_id" == "$plist_bundle_id" ]] || fail "bundle identifier mismatch: host=$host_bundle_id plist=$plist_bundle_id"
[[ "$host_bundle_id" == "$release_bundle_id" ]] || fail "bundle identifier mismatch: host=$host_bundle_id release-script=$release_bundle_id"
[[ "$host_min_os" == "$plist_min_os" ]] || fail "minimum macOS mismatch: host=$host_min_os plist=$plist_min_os"
[[ "$host_min_os" == "$package_min_os" ]] || fail "minimum macOS mismatch: host=$host_min_os package=$package_min_os"
[[ "$host_marketing_version" == "$plist_marketing_version" ]] || fail "marketing version mismatch: host=$host_marketing_version plist=$plist_marketing_version"
[[ "$host_build_number" == "$plist_build_number" ]] || fail "build number mismatch: host=$host_build_number plist=$plist_build_number"

echo "Build settings parity check passed"
