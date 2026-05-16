#!/bin/bash
# codex-wrapper.sh — launch OpenAI Codex CLI with in0 hook + notify wired in.
#
# Codex's experimental hooks are feature-gated and live in $CODEX_HOME/hooks.json;
# we don't want to mutate the user's real ~/.codex. Strategy: build a temporary
# CODEX_HOME overlay, symlink every existing entry through to the real dir,
# write our own hooks.json into the overlay, point CODEX_HOME at it, exec.

set -e

REAL_CODEX=""
if [ -n "${IN0_REAL_CODEX:-}" ] && [ -x "$IN0_REAL_CODEX" ]; then
    REAL_CODEX="$IN0_REAL_CODEX"
else
    for candidate in $(which -a codex 2>/dev/null); do
        resolved=$(readlink -f "$candidate" 2>/dev/null || echo "$candidate")
        case "$resolved" in
            *in0*agent-hooks*codex-wrapper*) continue ;;
        esac
        REAL_CODEX="$candidate"
        break
    done
fi

if [ -z "$REAL_CODEX" ]; then
    echo "in0 codex-wrapper: real 'codex' binary not found in PATH" >&2
    echo "  hint: install OpenAI Codex CLI, or export IN0_REAL_CODEX=/path/to/codex" >&2
    exit 127
fi

if [ -z "${IN0_AGENT_HOOKS_DIR:-}" ] || [ -z "${IN0_HOOK_SOCK:-}" ] || [ -z "${IN0_TERMINAL_ID:-}" ]; then
    exec "$REAL_CODEX" "$@"
fi

EMIT="$IN0_AGENT_HOOKS_DIR/hook-emit.sh"
AGENT_HOOK="$IN0_AGENT_HOOKS_DIR/agent-hook.sh"

OVERLAY=$(mktemp -d -t in0-codex.XXXXXX)
USER_HOME="${CODEX_HOME:-$HOME/.codex}"

# Mirror the user's CODEX_HOME into the overlay via symlinks so reads still
# see their real config. Skip hooks.json — we own that file. Codex writes
# config.toml via tempfile + rename(2), which atomically replaces the
# symlink with a regular file; the cleanup trap below detects that and
# syncs the file back to the real home so `codex features enable` / login
# changes persist across runs.
if [ -d "$USER_HOME" ]; then
    for item in "$USER_HOME"/*; do
        [ -e "$item" ] || continue
        name=$(basename "$item")
        case "$name" in
            hooks.json) continue ;;
        esac
        ln -sfn "$item" "$OVERLAY/$name"
    done
fi
if [ ! -e "$OVERLAY/config.toml" ] && [ ! -L "$OVERLAY/config.toml" ]; then
    mkdir -p "$USER_HOME"
    ln -sfn "$USER_HOME/config.toml" "$OVERLAY/config.toml"
fi

# Codex's hooks.json uses the same nested matcher-groups shape as Claude
# Code, parsed with serde's deny_unknown_fields — any stray key (or a flat
# {"command": ...} entry) silently skips the entire file. Schema reference:
# codex-rs/hooks/src/engine/config.rs.
cat > "$OVERLAY/hooks.json" <<EOF
{
  "hooks": {
    "SessionStart":     [{"hooks": [{"type": "command", "command": "$EMIT idle codex"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "$AGENT_HOOK prompt codex"}]}],
    "PreToolUse":       [{"hooks": [{"type": "command", "command": "$AGENT_HOOK pretool codex"}]}],
    "PostToolUse":      [{"hooks": [{"type": "command", "command": "$AGENT_HOOK posttool codex"}]}],
    "Stop":             [{"hooks": [{"type": "command", "command": "$AGENT_HOOK stop codex"}]}]
  }
}
EOF

export CODEX_HOME="$OVERLAY"

cleanup() {
    # If codex replaced the config.toml symlink with a regular file, copy
    # the new content back to the user's real CODEX_HOME so changes from
    # `codex features enable`, `codex login`, etc. persist.
    if [ -f "$OVERLAY/config.toml" ] && [ ! -L "$OVERLAY/config.toml" ]; then
        mkdir -p "$USER_HOME"
        cp -f "$OVERLAY/config.toml" "$USER_HOME/config.toml" 2>/dev/null || true
    fi
    rm -rf "$OVERLAY" 2>/dev/null || true
    "$EMIT" idle codex 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Emit idle now — the shell's preexec already flipped us to running when
# the user typed `codex`, but codex's own notify won't fire until the
# first turn completes. Without this, the UI sits on "running" from
# launch until the first turn finishes.
"$EMIT" idle codex 2>/dev/null || true

# Inject `notify` via -c so we don't have to mutate config.toml. `-c
# key=value` parses value as TOML (arrays work — see codex --help).
exec "$REAL_CODEX" -c "notify=[\"$EMIT\", \"idle\", \"codex\"]" "$@"
