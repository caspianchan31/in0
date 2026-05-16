#!/bin/bash
# Clean-rebuild and relaunch in0 Debug app from scratch (no cache).
# Useful when an Info.plist / rpath / signing change makes the OS
# refuse to relaunch the previous binary.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "==> Killing running in0…"
pkill -f "Debug/in0.app" 2>/dev/null || true
sleep 1

echo "==> Cleaning Xcode build cache…"
xcodebuild -project in0.xcodeproj -scheme in0 -configuration Debug clean >/dev/null

echo "==> Removing DerivedData for in0…"
rm -rf ~/Library/Developer/Xcode/DerivedData/in0-*

echo "==> Building (fresh)…"
xcodebuild -project in0.xcodeproj -scheme in0 -configuration Debug build | tail -3

APP=$(find ~/Library/Developer/Xcode/DerivedData -name "in0.app" -type d 2>/dev/null | head -1)
if [ -z "$APP" ]; then
  echo "!! in0.app not found after build" >&2
  exit 1
fi

echo "==> Refreshing LaunchServices registration for $APP"
# Force LS to forget stale cached info — otherwise `open` may keep
# launching the previous build's bundle when the rpath / Info.plist
# changed underneath it.
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "==> Launching: $APP"
open "$APP"
sleep 1
pgrep -lf "Debug/in0.app" || echo "!! launch failed"
