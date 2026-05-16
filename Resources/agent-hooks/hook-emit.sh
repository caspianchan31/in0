#!/bin/bash
# hook-emit.sh — wire-level event emitter.
#
# Sends one JSON line to the in0 hook socket. Called from every other piece
# in this directory: shell preexec/precmd, the agent CLI wrappers, and the
# Python turn tracker. Keeping the wire format in one place means changes
# to the schema only need to land here.
#
# Usage: hook-emit.sh <event> <agent> [timestamp] [exit_code]
#   event:     running | idle | needsInput | finished
#   agent:     shell | claude | codex | opencode
#   timestamp: optional epoch float; shells pass $EPOCHREALTIME so the
#              ordering between two `&!` hooks doesn't get inverted by
#              python's variable startup cost.
#   exit_code: integer — required iff event=finished; downgraded to `idle`
#              when missing/garbage so a malformed line doesn't crash the
#              decoder on the Swift side.

set -e

# Silent no-op outside in0 — the wrappers and shell hooks all exec this
# unconditionally, and a bare exit 0 makes them safe to run anywhere.
[ -z "${IN0_HOOK_SOCK:-}" ] && exit 0
[ -z "${IN0_TERMINAL_ID:-}" ] && exit 0

event="${1:-running}"
agent="${2:-shell}"
arg_now="${3:-}"
arg_exit="${4:-}"

if [[ "$arg_now" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    now="$arg_now"
else
    # Fish and bash 3.2 don't supply EPOCHREALTIME; fall back to python's
    # time.time() (portable) before `date +%s.%N` (Linux-only).
    now=$(python3 -c 'import time; print(time.time())' 2>/dev/null || echo "$(date +%s).0")
fi

if [ "$event" = "finished" ]; then
    if [[ "$arg_exit" =~ ^-?[0-9]+$ ]]; then
        payload="{\"terminalId\":\"$IN0_TERMINAL_ID\",\"event\":\"finished\",\"agent\":\"$agent\",\"at\":$now,\"exitCode\":$arg_exit}"
    else
        payload="{\"terminalId\":\"$IN0_TERMINAL_ID\",\"event\":\"idle\",\"agent\":\"$agent\",\"at\":$now}"
    fi
else
    payload="{\"terminalId\":\"$IN0_TERMINAL_ID\",\"event\":\"$event\",\"agent\":\"$agent\",\"at\":$now}"
fi

# Debug trace — every emit gets logged so we can verify hooks fire without
# attaching a debugger. Remove when the pipeline is stable.
log_dir="$HOME/Library/Caches/in0"
mkdir -p "$log_dir" 2>/dev/null
echo "[$now] event=$event agent=$agent tid=${IN0_TERMINAL_ID:0:8}${arg_exit:+ exit=$arg_exit}" >> "$log_dir/hook-emit.log" 2>/dev/null

# Bash has no native AF_UNIX client; use python (always present on macOS).
python3 - "$IN0_HOOK_SOCK" "$payload" <<'PY' 2>/dev/null || true
import sys, socket
sock_path, payload = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.settimeout(0.5)
try:
    s.connect(sock_path)
    s.sendall((payload + "\n").encode())
finally:
    s.close()
PY
