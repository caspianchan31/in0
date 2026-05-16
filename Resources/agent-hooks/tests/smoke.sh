#!/bin/bash
# smoke.sh — end-to-end test of agent-hook.{sh,py}.
#
# Spins up a Python AF_UNIX echo server on a tmp socket, fires every
# subcommand of agent-hook.py with handcrafted JSON payloads, and
# asserts the right messages reached the socket and the session file
# transitioned through the right states. Run from the repo root:
#
#   ./Resources/agent-hooks/tests/smoke.sh

set -e

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$HERE/.."

TMPDIR_LOCAL=$(mktemp -d -t in0-smoke.XXXXXX)
SOCK="$TMPDIR_LOCAL/hook.sock"
SESSION_FILE_OVERRIDE="$TMPDIR_LOCAL/sessions.json"
TRANSCRIPT="$TMPDIR_LOCAL/transcript.jsonl"
RECEIVED="$TMPDIR_LOCAL/received.log"

cleanup() {
    if [ -n "${SERVER_PID:-}" ] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID"
    fi
    rm -rf "$TMPDIR_LOCAL"
}
trap cleanup EXIT INT TERM

# Seed a transcript so the `stop` step has a summary to extract.
cat > "$TRANSCRIPT" <<'EOF'
{"role":"user","content":"refactor foo"}
{"role":"assistant","content":"I refactored Foo.swift."}
EOF

# Echo server: every accepted line is appended to RECEIVED.
python3 - "$SOCK" "$RECEIVED" <<'PY' &
import os, socket, sys
sock_path, log_path = sys.argv[1], sys.argv[2]
try: os.unlink(sock_path)
except FileNotFoundError: pass
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(sock_path)
s.listen(8)
with open(log_path, "w") as log:
    while True:
        conn, _ = s.accept()
        data = b""
        while True:
            chunk = conn.recv(4096)
            if not chunk: break
            data += chunk
        conn.close()
        log.write(data.decode())
        log.flush()
PY
SERVER_PID=$!
sleep 0.3   # let the server bind before the first client connects

export IN0_HOOK_SOCK="$SOCK"
export IN0_TERMINAL_ID="00000000-0000-0000-0000-000000000001"

# Drive agent-hook.py directly with the env vars its bash entry would
# normally set. Bypassing agent-hook.sh lets us pin the session file to
# our temp copy without touching ~/Library/Caches/in0/.
run_hook() {
    local sub="$1"; shift
    local agt="$1"; shift
    local payload="$1"; shift
    _IN0_SUBCMD="$sub" _IN0_AGENT="$agt" \
      _IN0_SESSION_FILE="$SESSION_FILE_OVERRIDE" \
      _IN0_PAYLOAD="$payload" \
      python3 "$SCRIPT_DIR/agent-hook.py"
}

# Scenario: prompt → pretool(Edit) → posttool(is_error=true) → stop
run_hook prompt   claude '{"session_id":"s1","transcript_path":"'"$TRANSCRIPT"'"}'
run_hook pretool  claude '{"session_id":"s1","tool_name":"Edit","tool_input":{"file_path":"/foo/bar/baz.swift"}}'
run_hook posttool claude '{"session_id":"s1","tool_name":"Edit","tool_response":{"is_error":true}}'
run_hook stop     claude '{"session_id":"s1"}'

sleep 0.3   # give the server a moment to flush its buffer

if ! grep -q '"event": "running"' "$RECEIVED"; then
    echo "FAIL: no running event in received log" >&2; exit 1
fi
if ! grep -q '"toolDetail": "Edit foo/bar/baz.swift"' "$RECEIVED"; then
    echo "FAIL: missing toolDetail" >&2; cat "$RECEIVED" >&2; exit 1
fi
if ! grep -q '"exitCode": 1' "$RECEIVED"; then
    echo "FAIL: stop did not emit exitCode 1" >&2; cat "$RECEIVED" >&2; exit 1
fi
if ! grep -q '"summary": "I refactored Foo.swift."' "$RECEIVED"; then
    echo "FAIL: summary missing from stop payload" >&2; cat "$RECEIVED" >&2; exit 1
fi
if grep -q '"s1"' "$SESSION_FILE_OVERRIDE"; then
    echo "FAIL: session entry s1 still present after stop" >&2
    cat "$SESSION_FILE_OVERRIDE" >&2; exit 1
fi

echo "SMOKE OK"
