#!/usr/bin/env bash
# Codesign an in0.app bundle with the Developer ID, then submit for
# notarization and staple the ticket. Invoked by release.sh.

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: $0 <path/to/in0.app>" >&2
  exit 1
fi
APP="$1"

: "${DEVELOPER_ID:?DEVELOPER_ID is required}"
: "${APPLE_ID:?APPLE_ID is required}"
: "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required}"
: "${APPLE_APP_PASSWORD:?APPLE_APP_PASSWORD is required}"

ENTITLEMENTS="$(dirname "$0")/../in0/in0.entitlements"

echo "→ codesign"
codesign \
  --force \
  --options runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$DEVELOPER_ID" \
  --deep \
  "$APP"

echo "→ verify"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP" || true

echo "→ zip for notarization"
ZIP="$APP.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ notarytool submit"
xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --team-id "$APPLE_TEAM_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --wait

echo "→ staple"
xcrun stapler staple "$APP"
rm -f "$ZIP"
