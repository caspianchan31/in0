#!/bin/bash
# claude-wrapper.sh — launch Claude Code with in0 lifecycle hooks injected.
#
# Strategy: shadow `claude` in interactive shells (via agent-functions.zsh
# etc.), so when the user types `claude` we run THIS instead. We find the
# real binary, build a Claude --settings JSON declaring our hooks, and
# exec into it. Falls back to a plain passthrough when the in0 env vars
# aren't set (script invoked outside in0).

set -e

{
    echo "[$(date +%s)] [claude-wrapper] invoked: args=$*  IN0_AGENT_HOOKS_DIR=${IN0_AGENT_HOOKS_DIR:+set}  IN0_HOOK_SOCK=${IN0_HOOK_SOCK:+set}  IN0_TERMINAL_ID=${IN0_TERMINAL_ID:+set}"
} >> "$HOME/Library/Caches/in0/hook-emit.log" 2>/dev/null || true

# Locate the real `claude`. Override via IN0_REAL_CLAUDE for unusual setups;
# otherwise walk PATH and skip any entry that resolves back to this wrapper.
REAL_CLAUDE=""
if [ -n "${IN0_REAL_CLAUDE:-}" ] && [ -x "$IN0_REAL_CLAUDE" ]; then
    REAL_CLAUDE="$IN0_REAL_CLAUDE"
else
    for candidate in $(which -a claude 2>/dev/null); do
        resolved=$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")
        case "$resolved" in
            *in0*agent-hooks*claude-wrapper*) continue ;;
        esac
        REAL_CLAUDE="$candidate"
        break
    done
fi

if [ -z "$REAL_CLAUDE" ]; then
    echo "in0 claude-wrapper: real 'claude' binary not found in PATH" >&2
    echo "  hint: install Claude Code (https://claude.com/code), or export IN0_REAL_CLAUDE=/path/to/claude" >&2
    exit 127
fi

# Passthrough when called outside in0 (user PATH still has the shadow but
# in0's env wasn't injected — likely an unrelated terminal app).
if [ -z "${IN0_AGENT_HOOKS_DIR:-}" ] || [ -z "${IN0_HOOK_SOCK:-}" ] || [ -z "${IN0_TERMINAL_ID:-}" ]; then
    exec "$REAL_CLAUDE" "$@"
fi

EMIT="$IN0_AGENT_HOOKS_DIR/hook-emit.sh"
AGENT_HOOK="$IN0_AGENT_HOOKS_DIR/agent-hook.sh"

# Claude Code v2 hook schema: each event → array of matcher-groups; each
# group has an empty matcher + a nested hooks list of {type, command}.
# A flat {"command": "..."} silently fails to parse — the nested shape is
# what Claude actually accepts.
#
# UserPromptSubmit / PreToolUse / PostToolUse / Stop route to agent-hook.sh
# so we get per-turn state (resume command, tool detail, transcript
# summary). SessionStart / SessionEnd / Notification go straight through
# hook-emit.sh — they only need to broadcast a state.
SETTINGS_JSON=$(cat <<EOF
{
  "hooks": {
    "SessionStart":     [{"matcher": "", "hooks": [{"type": "command", "command": "$EMIT idle claude"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK prompt claude"}]}],
    "PreToolUse":       [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK pretool claude"}]}],
    "PostToolUse":      [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK posttool claude"}]}],
    "Stop":             [{"matcher": "", "hooks": [{"type": "command", "command": "$AGENT_HOOK stop claude"}]}],
    "Notification":     [{"matcher": "", "hooks": [{"type": "command", "command": "$EMIT needsInput claude"}]}],
    "SessionEnd":       [{"matcher": "", "hooks": [{"type": "command", "command": "$EMIT idle claude"}]}]
  }
}
EOF
)

{
    echo "[$(date +%s)] [claude-wrapper] execing: $REAL_CLAUDE --settings <json> $*"
    echo "[$(date +%s)] [claude-wrapper] SETTINGS_JSON=$SETTINGS_JSON"
} >> "$HOME/Library/Caches/in0/hook-emit.log" 2>/dev/null || true

# --settings merges with the user's own settings.json (we deliberately don't
# pass --setting-sources, which would disable their model/tool config).
exec "$REAL_CLAUDE" --settings "$SETTINGS_JSON" "$@"
