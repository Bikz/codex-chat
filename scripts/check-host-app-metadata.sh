#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="$ROOT/apps/CodexChatHost/CodexChatHost/Info.plist"
ICONSET_DIR="$ROOT/apps/CodexChatHost/CodexChatHost/Assets.xcassets/AppIcon.appiconset"
ICNS_FILE="$ROOT/apps/CodexChatHost/CodexChatHost/Resources/AppIcon.icns"

[[ -f "$INFO_PLIST" ]] || { echo "error: missing $INFO_PLIST" >&2; exit 1; }
[[ -d "$ICONSET_DIR" ]] || { echo "error: missing $ICONSET_DIR" >&2; exit 1; }
[[ -f "$ICNS_FILE" ]] || { echo "error: missing $ICNS_FILE" >&2; exit 1; }

bundle_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)
if [[ "$bundle_id" != "com.codexchat.app" ]]; then
  echo "error: host app bundle identifier must be com.codexchat.app (got '$bundle_id')" >&2
  exit 1
fi

min_os=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST" 2>/dev/null || true)
if [[ "$min_os" != "14.0" ]]; then
  echo "error: host app LSMinimumSystemVersion must be 14.0 (got '$min_os')" >&2
  exit 1
fi

for required in Contents.json icon_16x16.png icon_16x16@2x.png icon_32x32.png icon_32x32@2x.png icon_128x128.png icon_128x128@2x.png icon_256x256.png icon_256x256@2x.png icon_512x512.png icon_512x512@2x.png; do
  [[ -f "$ICONSET_DIR/$required" ]] || { echo "error: missing icon asset $required" >&2; exit 1; }
done

echo "Host app metadata check passed"
