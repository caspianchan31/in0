# bootstrap.zsh — source this from ~/.zshrc to enable in0 status hooks.
# Suggested rc snippet:
#   [ -f "$IN0_AGENT_HOOKS_DIR/bootstrap.zsh" ] && source "$IN0_AGENT_HOOKS_DIR/bootstrap.zsh"
[ -z "${IN0_AGENT_HOOKS_DIR:-}" ] && return 0
source "$IN0_AGENT_HOOKS_DIR/agent-functions.zsh" 2>/dev/null
