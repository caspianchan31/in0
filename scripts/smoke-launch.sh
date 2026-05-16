#!/usr/bin/env bash
# Build Debug, launch the .app, wait briefly, then check it's still alive.
# Used as a quick "did anything blow up at startup" check before merging.
#
# Cleanup behavior (important — broke once before):
#   - We launch via `open -n` (no -W). Using -W would wait for the launched
#     app to exit, which means the script never returns while in0 is alive.
#   - On success we send SIGTERM to the in0 process explicitly, then SIGKILL
#     if it didn't go down within ~2s. `killall in0` is unreliable on macOS
#     when an Xcode debugger holds the process — we work around by matching
#     the actual `.app/Contents/MacOS/in0` path so we hit OUR launch.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LAUNCH_TIMEOUT="${LAUNCH_TIMEOUT:-6}"
APP_GREP="in0.app/Contents/MacOS/in0"

echo "→ build Debug"
xcodebuild \
  -project in0.xcodeproj \
  -scheme in0 \
  -configuration Debug \
  build >/tmp/in0-smoke-build.log 2>&1 || { tail -30 /tmp/in0-smoke-build.log; exit 1; }

APP_PATH=$(xcodebuild -project in0.xcodeproj -scheme in0 -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/CONFIGURATION_BUILD_DIR/ {print $2; exit}')/in0.app

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: built .app missing at $APP_PATH" >&2
  exit 1
fi

# Refuse to fight an Xcode debug session — its in0 carries
# -NSDocumentRevisionsDebugMode and resists SIGKILL. Bail with a clear hint.
if pgrep -f "${APP_GREP} -NSDocumentRevisionsDebugMode" >/dev/null; then
  echo "FAIL: Xcode debug session is holding in0. Stop the run in Xcode (⌘.) and retry." >&2
  exit 2
fi

# Wipe persisted state so first-launch paths fire (hook installer, etc).
pkill -f "$APP_GREP" 2>/dev/null || true
defaults delete com.local.in0 2>/dev/null || true
rm -f ~/Library/Caches/in0/hooks-*.sock 2>/dev/null || true

codesign --force --sign - "$APP_PATH" >/dev/null 2>&1

echo "→ open + wait ${LAUNCH_TIMEOUT}s"
open -n "$APP_PATH"
sleep "$LAUNCH_TIMEOUT"

if ! pgrep -f "$APP_GREP" >/dev/null; then
  echo "FAIL: in0 exited within ${LAUNCH_TIMEOUT}s — check Console.app for crash report" >&2
  exit 1
fi

echo "OK: in0 still alive after ${LAUNCH_TIMEOUT}s"

# Polite shutdown: try SIGTERM, give it up to 2s, then SIGKILL.
pkill -TERM -f "$APP_GREP" 2>/dev/null || true
for _ in 1 2 3 4; do
  sleep 0.5
  pgrep -f "$APP_GREP" >/dev/null || break
done
pkill -9 -f "$APP_GREP" 2>/dev/null || true
exit 0
