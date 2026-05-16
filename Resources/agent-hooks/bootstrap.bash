# bootstrap.bash — source this from ~/.bashrc to enable in0 status hooks.
# Suggested rc snippet:
#   [ -f "$IN0_AGENT_HOOKS_DIR/bootstrap.bash" ] && source "$IN0_AGENT_HOOKS_DIR/bootstrap.bash"
[ -z "${IN0_AGENT_HOOKS_DIR:-}" ] && return 0
source "$IN0_AGENT_HOOKS_DIR/agent-functions.bash" 2>/dev/null
