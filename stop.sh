#!/bin/bash
# Terminate any running in0 Debug instance. SIGTERM first, SIGKILL
# fallback if the process isn't down within ~1s.

set -e

echo "==> Killing running in0…"
pkill -f "Debug/in0.app" 2>/dev/null || true
sleep 1

if pgrep -lf "Debug/in0.app" >/dev/null; then
  echo "!! in0 still running, sending SIGKILL"
  pkill -9 -f "Debug/in0.app" 2>/dev/null || true
  sleep 1
fi

if pgrep -lf "Debug/in0.app" >/dev/null; then
  echo "!! failed to terminate in0" >&2
  exit 1
else
  echo "==> in0 terminated"
fi
