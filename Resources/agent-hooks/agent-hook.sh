#!/bin/bash
# agent-hook.sh — thin bash entry to agent-hook.py.
#
# Claude Code / Codex hand the hook process a JSON payload on stdin; the
# python script needs both the payload and the subcommand context. We stash
# them in env vars (PAYLOAD is small, <4 KB) so python doesn't need to
# re-parse argv conventions or read stdin a second time.
#
# Usage: agent-hook.sh <subcommand> <agent>
#   subcommand: prompt | pretool | posttool | stop
#   agent:      claude | codex

set -e

[ -z "${IN0_HOOK_SOCK:-}" ] && exit 0
[ -z "${IN0_TERMINAL_ID:-}" ] && exit 0

subcmd="${1:-stop}"
agent="${2:-claude}"
script_dir="$(dirname "${BASH_SOURCE[0]}")"

export _IN0_SUBCMD="$subcmd"
export _IN0_AGENT="$agent"
export _IN0_SESSION_FILE="${HOME}/Library/Caches/in0/agent-sessions.json"
export _IN0_PAYLOAD
_IN0_PAYLOAD="$(cat)"

exec python3 "$script_dir/agent-hook.py"
