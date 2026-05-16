#!/usr/bin/env bash
# Build a DMG containing the signed, notarized in0.app. Uses create-dmg
# (brew install create-dmg) if available; otherwise falls back to hdiutil.

set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <path/to/in0.app> <out.dmg>" >&2
  exit 1
fi
APP="$1"
DMG="$2"

if command -v create-dmg >/dev/null; then
  create-dmg \
    --volname "in0" \
    --window-size 540 360 \
    --icon-size 96 \
    --icon "in0.app" 130 180 \
    --app-drop-link 410 180 \
    --hide-extension "in0.app" \
    --no-internet-enable \
    "$DMG" "$APP"
else
  echo "create-dmg missing; using hdiutil"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create \
    -volname "in0" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"
fi
