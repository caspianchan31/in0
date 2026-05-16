# bootstrap.fish — source from ~/.config/fish/config.fish to enable in0 status hooks.
# Suggested rc snippet:
#   if set -q IN0_AGENT_HOOKS_DIR
#       source "$IN0_AGENT_HOOKS_DIR/bootstrap.fish"
#   end
test -z "$IN0_AGENT_HOOKS_DIR"; and return 0
test -f "$IN0_AGENT_HOOKS_DIR/agent-functions.fish"; and source "$IN0_AGENT_HOOKS_DIR/agent-functions.fish"
