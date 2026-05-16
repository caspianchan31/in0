# agent-functions.fish — shadow agent CLI names with in0 wrapper invocations.
# Called from bootstrap.fish.
test -z "$IN0_AGENT_HOOKS_DIR"; and return 0

function claude
    command "$IN0_AGENT_HOOKS_DIR/claude-wrapper.sh" $argv
end

function opencode
    command "$IN0_AGENT_HOOKS_DIR/opencode-wrapper.sh" $argv
end

function codex
    command "$IN0_AGENT_HOOKS_DIR/codex-wrapper.sh" $argv
end
