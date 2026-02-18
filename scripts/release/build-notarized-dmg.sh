#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

APP_PRODUCT_NAME="${APP_PRODUCT_NAME:-CodexChat}"
APP_EXECUTABLE_NAME="${APP_EXECUTABLE_NAME:-CodexChatApp}"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-com.codexchat.app}"
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
BUILD_DIR="$WORK_DIR/.build"
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

locate_release_binary() {
  local direct="$BUILD_DIR/release/$APP_EXECUTABLE_NAME"
  if [[ -x "$direct" ]]; then
    echo "$direct"
    return 0
  fi

  local candidate
  candidate="$(find "$BUILD_DIR" -type f -name "$APP_EXECUTABLE_NAME" -path "*/release/*" | head -n 1 || true)"
  [[ -n "$candidate" ]] || fail "unable to locate release binary ($APP_EXECUTABLE_NAME)"
  echo "$candidate"
}

locate_resource_bundle() {
  local candidate
  candidate="$(find "$BUILD_DIR" -type d -name "*_CodexChatApp.bundle" -path "*/release/*" | head -n 1 || true)"
  [[ -n "$candidate" ]] || fail "unable to locate SwiftPM resource bundle for CodexChatApp"
  echo "$candidate"
}

ensure_expected_arch() {
  local actual_arch
  actual_arch="$(uname -m)"
  if [[ "$actual_arch" != "$TARGET_ARCH" ]]; then
    fail "build host architecture is $actual_arch, expected $TARGET_ARCH"
  fi
}

build_release_binary() {
  echo "Building release binary..."
  rm -rf "$BUILD_DIR"
  (cd "$ROOT/apps/CodexChatApp" && swift build -c release --scratch-path "$BUILD_DIR")
}

create_app_bundle() {
  local binary_path="$1"
  local resource_bundle_path="$2"

  echo "Assembling app bundle..."
  rm -rf "$APP_BUNDLE_PATH"
  mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS"
  mkdir -p "$APP_BUNDLE_PATH/Contents/Resources"

  cp "$binary_path" "$APP_BUNDLE_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME"
  chmod +x "$APP_BUNDLE_PATH/Contents/MacOS/$APP_EXECUTABLE_NAME"

  cp -R "$resource_bundle_path" "$APP_BUNDLE_PATH/Contents/Resources/"

  cat > "$APP_BUNDLE_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>$APP_PRODUCT_NAME</string>
  <key>CFBundleExecutable</key>
  <string>$APP_EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_PRODUCT_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
EOF
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
  spctl --assess --type execute --verbose "$path"
}

notarize_and_staple() {
  local path="$1"
  echo "Notarizing $path"
  xcrun notarytool submit \
    "$path" \
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

  xcrun stapler validate "$path"

  if [[ "$kind" == "dmg" ]]; then
    spctl --assess --type open --verbose "$path"
    return 0
  fi

  spctl --assess --type execute --verbose "$path"
}

create_dmg() {
  local dmg_source="$WORK_DIR/dmg-root"
  rm -rf "$dmg_source"
  mkdir -p "$dmg_source"
  cp -R "$APP_BUNDLE_PATH" "$dmg_source/"

  echo "Creating DMG..."
  rm -f "$DMG_PATH"
  hdiutil create -volname "$APP_PRODUCT_NAME" -srcfolder "$dmg_source" -ov -format UDZO "$DMG_PATH"
}

main() {
  require_command swift
  require_command hdiutil
  require_command xcrun
  require_command shasum
  require_command uname

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

  build_release_binary

  local binary_path
  binary_path="$(locate_release_binary)"
  local resource_bundle_path
  resource_bundle_path="$(locate_resource_bundle)"
  create_app_bundle "$binary_path" "$resource_bundle_path"

  if [[ "$SKIP_SIGNING" != "1" ]]; then
    sign_item "$APP_BUNDLE_PATH" "app"
    verify_signature "$APP_BUNDLE_PATH"
  fi

  if [[ "$SKIP_NOTARIZATION" != "1" ]]; then
    notarize_and_staple "$APP_BUNDLE_PATH"
    validate_notarized_item "$APP_BUNDLE_PATH" "app"
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
