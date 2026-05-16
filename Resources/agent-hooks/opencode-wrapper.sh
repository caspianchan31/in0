#!/bin/bash
# opencode-wrapper.sh — launch opencode with the in0 status plugin installed.
#
# opencode auto-discovers plugins from `~/.config/opencode/plugins/`. We
# symlink our bundled plugin into that dir on every launch (skipping the
# work if the symlink already points at our copy). This way the user
# doesn't need a separate "install plugin" step — opening opencode through
# in0 sets it up.

set -e

REAL_OPENCODE=""
if [ -n "${IN0_REAL_OPENCODE:-}" ] && [ -x "$IN0_REAL_OPENCODE" ]; then
    REAL_OPENCODE="$IN0_REAL_OPENCODE"
else
    for candidate in $(which -a opencode 2>/dev/null); do
        resolved=$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")
        case "$resolved" in
            *in0*agent-hooks*opencode-wrapper*) continue ;;
        esac
        REAL_OPENCODE="$candidate"
        break
    done
fi

if [ -z "$REAL_OPENCODE" ]; then
    echo "in0 opencode-wrapper: real 'opencode' binary not found in PATH" >&2
    echo "  hint: install opencode (https://opencode.ai), or export IN0_REAL_OPENCODE=/path/to/opencode" >&2
    exit 127
fi

if [ -z "${IN0_AGENT_HOOKS_DIR:-}" ] || [ -z "${IN0_HOOK_SOCK:-}" ] || [ -z "${IN0_TERMINAL_ID:-}" ]; then
    exec "$REAL_OPENCODE" "$@"
fi

PLUGIN_SRC="$IN0_AGENT_HOOKS_DIR/opencode-plugin/in0-status.js"
USER_PLUGINS="$HOME/.config/opencode/plugins"
mkdir -p "$USER_PLUGINS"
LINK="$USER_PLUGINS/in0-status.js"

if [ ! -e "$LINK" ] || [ "$(readlink "$LINK" 2>/dev/null)" != "$PLUGIN_SRC" ]; then
    rm -f "$LINK"
    ln -s "$PLUGIN_SRC" "$LINK"
fi

EMIT="$IN0_AGENT_HOOKS_DIR/hook-emit.sh"

# Mark idle on exit — opencode's session.idle event may not fire promptly
# if the window is force-closed, leaving the status icon stuck on running.
trap '"$EMIT" idle opencode 2>/dev/null || true' EXIT INT TERM

# Emit idle BEFORE exec. The shell's preexec just flipped us to running
# (user typed `opencode`), but opencode's session.created fires later;
# without this the icon hangs on running until the plugin connects.
"$EMIT" idle opencode 2>/dev/null || true

exec "$REAL_OPENCODE" "$@"
