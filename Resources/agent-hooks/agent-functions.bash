# agent-functions.bash — shadow agent CLI names so they route through the
# in0 wrappers. Called from bootstrap.bash. Functions, not aliases, so
# argument forwarding via "$@" works without quoting tricks.
[ -z "${IN0_AGENT_HOOKS_DIR:-}" ] && return 0

claude()   { command "$IN0_AGENT_HOOKS_DIR/claude-wrapper.sh"   "$@"; }
opencode() { command "$IN0_AGENT_HOOKS_DIR/opencode-wrapper.sh" "$@"; }
codex()    { command "$IN0_AGENT_HOOKS_DIR/codex-wrapper.sh"    "$@"; }

export -f claude opencode codex 2>/dev/null || true
