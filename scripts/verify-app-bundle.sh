#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-}"
EXPECTED_BUNDLE_ID="${EXPECTED_BUNDLE_ID:-com.codexchat.app}"
EXPECTED_MIN_OS="${EXPECTED_MIN_OS:-14.0}"
REQUIRE_SIGNATURE="${REQUIRE_SIGNATURE:-1}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -n "$APP_PATH" ]] || fail "usage: scripts/verify-app-bundle.sh <path-to-app>"
[[ -d "$APP_PATH" ]] || fail "app bundle not found: $APP_PATH"

plist="$APP_PATH/Contents/Info.plist"
[[ -f "$plist" ]] || fail "missing Info.plist in app bundle"

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)
short_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)
build_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)
min_os=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist" 2>/dev/null || true)

[[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || fail "bundle ID mismatch: expected=$EXPECTED_BUNDLE_ID actual=$bundle_id"
[[ -n "$short_version" ]] || fail "missing CFBundleShortVersionString"
[[ -n "$build_version" ]] || fail "missing CFBundleVersion"
[[ "$min_os" == "$EXPECTED_MIN_OS" ]] || fail "minimum OS mismatch: expected=$EXPECTED_MIN_OS actual=$min_os"

[[ -f "$APP_PATH/Contents/Resources/AppIcon.icns" ]] || fail "missing app icon resource at Contents/Resources/AppIcon.icns"
[[ -f "$APP_PATH/Contents/Resources/Assets.car" ]] || fail "missing compiled asset catalog (Assets.car)"

if [[ "$REQUIRE_SIGNATURE" == "1" ]]; then
  command -v codesign >/dev/null 2>&1 || fail "codesign command not available"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"

  codesign_details="$(codesign -dv --verbose=4 "$APP_PATH" 2>&1 || true)"
  grep -F "Identifier=$EXPECTED_BUNDLE_ID" <<<"$codesign_details" >/dev/null || fail "signed identifier mismatch"
  grep -F "Runtime Version" <<<"$codesign_details" >/dev/null || fail "hardened runtime missing"
fi

if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
  command -v xcrun >/dev/null 2>&1 || fail "xcrun command not available"
  xcrun stapler validate "$APP_PATH"
fi

echo "App bundle verification passed: $APP_PATH"
