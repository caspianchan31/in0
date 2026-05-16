# agent-functions.zsh — shadow agent CLI names with in0 wrapper invocations.
# Called from bootstrap.zsh.
[ -z "${IN0_AGENT_HOOKS_DIR:-}" ] && return 0

# zsh expands aliases at PARSE TIME on function-name positions. If the user
# has `alias claude='claude --skip-perms'`, writing `claude() { ... }` parses
# as `claude --skip-perms() { ... }` and breaks. The `\name` form disables
# alias expansion on that token (functions remain definable). At command
# sites the alias still expands to the user's preferred flags, then resolves
# the first word to our function — both layers stay happy.

\claude() {
    command "$IN0_AGENT_HOOKS_DIR/claude-wrapper.sh" "$@"
}

\opencode() {
    command "$IN0_AGENT_HOOKS_DIR/opencode-wrapper.sh" "$@"
}

\codex() {
    command "$IN0_AGENT_HOOKS_DIR/codex-wrapper.sh" "$@"
}
