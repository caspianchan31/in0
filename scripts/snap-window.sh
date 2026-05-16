#!/usr/bin/env bash
# Launch the Debug build, wait until the in0 window appears, then capture
# the window region as a PNG. The path is printed on success so callers
# (and the developer) can `Read` it for visual verification.
#
# Usage:
#   ./scripts/snap-window.sh                  → /tmp/in0-snap.png
#   ./scripts/snap-window.sh path/to/out.png  → custom path
#
# Why this exists: the older `smoke-launch.sh` only checked "still alive
# after 6s", which let me ship a release-blocker (window-eating blur layer)
# without noticing. Every UI change must now be visually verified via this
# script before the change is reported as done.

set -euo pipefail

OUT="${1:-/tmp/in0-snap.png}"
mkdir -p "$(dirname "$OUT")"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Build (output suppressed unless it fails).
if ! xcodebuild -project in0.xcodeproj -scheme in0 -configuration Debug build \
     >/tmp/in0-snap-build.log 2>&1; then
  tail -40 /tmp/in0-snap-build.log
  exit 1
fi

APP=$(xcodebuild -project in0.xcodeproj -scheme in0 -configuration Debug \
        -showBuildSettings 2>/dev/null \
      | awk -F' = ' '/CONFIGURATION_BUILD_DIR/ {print $2; exit}')/in0.app

# Xcode's debug runs carry the -NSDocumentRevisionsDebugMode flag and resist
# SIGKILL (lldb holds them). If one exists, bail with a clear hint so the
# user can stop the debug session before retrying — fighting it produces
# zombie processes with no windows.
if pgrep -f "in0.app/Contents/MacOS/in0 -NSDocumentRevisionsDebugMode" >/dev/null; then
  echo "FAIL: Xcode debug session is holding in0. Stop the run in Xcode (⌘.) then retry." >&2
  exit 2
fi

pkill -9 -f "in0.app/Contents/MacOS" 2>/dev/null || true
sleep 0.5

codesign --force --sign - "$APP" >/dev/null 2>&1
open -n "$APP"

# Poll for the window. SwiftUI launch + ghostty init + first surface usually
# settles within a couple seconds; cap at 12s before bailing.
BOUNDS=""
for _ in $(seq 1 24); do
  sleep 0.5
  BOUNDS=$(osascript <<'EOF' 2>/dev/null || true
tell application "in0" to activate
delay 0.1
tell application "System Events" to tell process "in0"
  if (count of windows) = 0 then return ""
  repeat with w in windows
    set p to position of w
    set s to size of w
    if (item 1 of s) > 200 then
      return ((item 1 of p) as text) & "," & ((item 2 of p) as text) & "," & ((item 1 of s) as text) & "," & ((item 2 of s) as text)
    end if
  end repeat
  return ""
end tell
EOF
  )
  [ -n "$BOUNDS" ] && break
done

if [ -z "$BOUNDS" ]; then
  echo "FAIL: in0 window did not appear within 12s" >&2
  pkill -9 -f "in0.app/Contents/MacOS" 2>/dev/null || true
  exit 1
fi

# Give the chrome one more frame to settle.
sleep 0.4
screencapture -R "$BOUNDS" -x "$OUT"
pkill -9 -f "in0.app/Contents/MacOS" 2>/dev/null || true
echo "OK: window snapshot at $OUT"
