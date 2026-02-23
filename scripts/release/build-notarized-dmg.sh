#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

HOST_PROJECT_PATH="${HOST_PROJECT_PATH:-$ROOT/apps/CodexChatHost/CodexChatHost.xcodeproj}"
HOST_SCHEME="${HOST_SCHEME:-CodexChatHost}"
APP_PRODUCT_NAME="${APP_PRODUCT_NAME:-CodexChat}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.codexchat.app}"
APP_CATEGORY_TYPE="${APP_CATEGORY_TYPE:-public.app-category.developer-tools}"
VERSION="${VERSION:-${GITHUB_REF_NAME:-dev}}"
VERSION="${VERSION#refs/tags/}"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-1}}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
TARGET_ARCH="${TARGET_ARCH:-arm64}"

SKIP_SIGNING="${SKIP_SIGNING:-0}"
SKIP_NOTARIZATION="${SKIP_NOTARIZATION:-0}"

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
NOTARY_KEY_ID="${NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID:-}"
NOTARY_KEY_FILE="${NOTARY_KEY_FILE:-}"

WORK_DIR="$ROOT/.release-work/$VERSION"
ARCHIVE_PATH="$WORK_DIR/$HOST_SCHEME.xcarchive"
APP_BUNDLE_PATH="$WORK_DIR/$APP_PRODUCT_NAME.app"
DMG_NAME="$APP_PRODUCT_NAME-$VERSION.dmg"
DMG_PATH="$WORK_DIR/$DMG_NAME"

fail() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "required command missing: $1"
  fi
}

require_env() {
  local name="$1"
  local value="${!name:-}"
  if [[ -z "$value" ]]; then
    fail "required environment variable missing: $name"
  fi
}

ensure_expected_arch() {
  local actual_arch
  actual_arch="$(uname -m)"
  if [[ "$actual_arch" != "$TARGET_ARCH" ]]; then
    fail "build host architecture is $actual_arch, expected $TARGET_ARCH"
  fi
}

set_plist_value() {
  local plist_path="$1"
  local key="$2"
  local value="$3"

  if /usr/libexec/PlistBuddy -c "Print :$key" "$plist_path" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist_path"
  else
    /usr/libexec/PlistBuddy -c "Add :$key string $value" "$plist_path"
  fi
}

build_release_app_from_host_archive() {
  echo "Building host archive..."
  rm -rf "$ARCHIVE_PATH" "$APP_BUNDLE_PATH"

  xcodebuild \
    -quiet \
    -project "$HOST_PROJECT_PATH" \
    -scheme "$HOST_SCHEME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    archive

  local archived_app
  archived_app="$(find "$ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
  [[ -n "$archived_app" ]] || fail "unable to locate archived .app at $ARCHIVE_PATH/Products/Applications"

  cp -R "$archived_app" "$APP_BUNDLE_PATH"

  local plist="$APP_BUNDLE_PATH/Contents/Info.plist"
  [[ -f "$plist" ]] || fail "missing Info.plist in archived app bundle"

  set_plist_value "$plist" "CFBundleIdentifier" "$APP_BUNDLE_ID"
  set_plist_value "$plist" "CFBundleShortVersionString" "$VERSION"
  set_plist_value "$plist" "CFBundleVersion" "$BUILD_NUMBER"
  set_plist_value "$plist" "LSApplicationCategoryType" "$APP_CATEGORY_TYPE"
}

sign_item() {
  local path="$1"
  local kind="${2:-generic}"
  echo "Signing $path"
  if [[ "$kind" == "app" ]]; then
    codesign --force --timestamp --options runtime --sign "$CODESIGN_IDENTITY" "$path"
    return 0
  fi

  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$path"
}

verify_signature() {
  local path="$1"
  codesign --verify --deep --strict --verbose=2 "$path"
}

notarize_and_staple() {
  local path="$1"
  local upload_path="$path"

  if [[ "$path" == *.app ]]; then
    upload_path="$WORK_DIR/$(basename "$path").zip"
    rm -f "$upload_path"
    ditto -c -k --sequesterRsrc --keepParent "$path" "$upload_path"
  fi

  echo "Notarizing $path"
  xcrun notarytool submit \
    "$upload_path" \
    --key "$NOTARY_KEY_FILE" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait
  echo "Stapling $path"
  xcrun stapler staple "$path"
}

validate_notarized_item() {
  local path="$1"
  local kind="$2"
  local spctl_output
  spctl_output="$(mktemp)"

  xcrun stapler validate "$path"

  if [[ "$kind" == "dmg" ]]; then
    if ! spctl --assess --type open --verbose "$path" >"$spctl_output" 2>&1; then
      if grep -qi "Insufficient Context" "$spctl_output"; then
        cat "$spctl_output"
        echo "warning: spctl open assessment returned 'Insufficient Context'; continuing because notarization + stapler validation succeeded." >&2
        rm -f "$spctl_output"
        return 0
      fi

      cat "$spctl_output" >&2
      rm -f "$spctl_output"
      return 1
    fi

    cat "$spctl_output"
    rm -f "$spctl_output"
    return 0
  fi

  if ! spctl --assess --type execute --verbose "$path" >"$spctl_output" 2>&1; then
    cat "$spctl_output" >&2
    rm -f "$spctl_output"
    return 1
  fi

  cat "$spctl_output"
  rm -f "$spctl_output"
}

create_dmg() {
  local dmg_source="$WORK_DIR/dmg-root"
  rm -rf "$dmg_source"
  mkdir -p "$dmg_source"
  cp -R "$APP_BUNDLE_PATH" "$dmg_source/"
  ln -s /Applications "$dmg_source/Applications"

  echo "Creating DMG..."
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_PRODUCT_NAME" -srcfolder "$dmg_source" -ov -format UDZO "$DMG_PATH"
}

main() {
  require_command xcodebuild
  require_command hdiutil
  require_command xcrun
  require_command shasum
  require_command uname

  "$ROOT/scripts/check-host-app-metadata.sh"
  "$ROOT/scripts/verify-build-settings-parity.sh"

  mkdir -p "$WORK_DIR"
  mkdir -p "$DIST_DIR"
  ensure_expected_arch

  if [[ "$SKIP_NOTARIZATION" != "1" && "$SKIP_SIGNING" == "1" ]]; then
    fail "notarization requires signing; remove SKIP_SIGNING or set SKIP_NOTARIZATION=1"
  fi

  if [[ "$SKIP_SIGNING" != "1" ]]; then
    require_command codesign
    require_command spctl
    require_env CODESIGN_IDENTITY
  fi

  if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    require_env NOTARY_KEY_ID
    require_env NOTARY_ISSUER_ID
    require_env NOTARY_KEY_FILE
    [[ -f "$NOTARY_KEY_FILE" ]] || fail "NOTARY_KEY_FILE does not exist: $NOTARY_KEY_FILE"
    xcrun notarytool --version >/dev/null
  fi

  build_release_app_from_host_archive

  if [[ "$SKIP_SIGNING" != "1" ]]; then
    sign_item "$APP_BUNDLE_PATH" "app"
    verify_signature "$APP_BUNDLE_PATH"
  fi

  REQUIRE_SIGNATURE=$([[ "$SKIP_SIGNING" == "1" ]] && echo 0 || echo 1) \
  REQUIRE_NOTARIZATION=0 \
  EXPECTED_BUNDLE_ID="$APP_BUNDLE_ID" \
  "$ROOT/scripts/verify-app-bundle.sh" "$APP_BUNDLE_PATH"

  if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    notarize_and_staple "$APP_BUNDLE_PATH"
    validate_notarized_item "$APP_BUNDLE_PATH" "app"

    REQUIRE_SIGNATURE=1 \
    REQUIRE_NOTARIZATION=1 \
    EXPECTED_BUNDLE_ID="$APP_BUNDLE_ID" \
    "$ROOT/scripts/verify-app-bundle.sh" "$APP_BUNDLE_PATH"
  fi

  create_dmg

  if [[ "$SKIP_SIGNING" != "1" ]]; then
    sign_item "$DMG_PATH" "dmg"
  fi

  if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    notarize_and_staple "$DMG_PATH"
    validate_notarized_item "$DMG_PATH" "dmg"
  fi

  local final_dmg="$DIST_DIR/$DMG_NAME"
  cp "$DMG_PATH" "$final_dmg"
  shasum -a 256 "$final_dmg" > "$final_dmg.sha256"

  if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    validate_notarized_item "$final_dmg" "dmg"
  fi

  echo "Release artifacts:"
  echo "  $final_dmg"
  echo "  $final_dmg.sha256"
}

main "$@"
