# in0 zsh shim .zshenv — installed via ZDOTDIR hijack from GhosttyBridge.
# Four jobs, in order:
#   1. Restore the user's original ZDOTDIR so subsequent .zprofile / .zshrc /
#      .zlogin lookups resolve against their real config dir, not ours.
#   2. Source the user's real .zshenv (zsh won't re-read it after we change
#      ZDOTDIR, so we have to do it explicitly).
#   3. Load ghostty's zsh integration. The standalone ghostty.app does this
#      via its own ZDOTDIR swap; libghostty linked as a static lib (our
#      case) never sets GHOSTTY_RESOURCES_DIR / GHOSTTY_ZSH_ZDOTDIR. Without
#      this, OSC 7 (pwd) and OSC 133 (prompt marks) never fire — sidebar
#      git branch + pwd inheritance break.
#   4. Defer bootstrap.zsh to the first precmd, AFTER .zshrc, so we append
#      to the user's preexec/precmd arrays instead of being overwritten.

# ── 1. Restore ZDOTDIR ─────────────────────────────────────────────────
if [ -n "${IN0_ORIG_ZDOTDIR+X}" ]; then
    export ZDOTDIR="$IN0_ORIG_ZDOTDIR"
    unset IN0_ORIG_ZDOTDIR
else
    unset ZDOTDIR
fi

# ── 2. Source user's real .zshenv ──────────────────────────────────────
_in0_user_zshenv="${ZDOTDIR:-$HOME}/.zshenv"
if [ -r "$_in0_user_zshenv" ]; then
    source "$_in0_user_zshenv"
fi
unset _in0_user_zshenv

# ── 3. Ghostty zsh integration ─────────────────────────────────────────
# IN0_AGENT_HOOKS_DIR points at <Resources>/agent-hooks; ghostty's
# integration script is a sibling at <Resources>/ghostty/shell-integration/
# zsh/ghostty-integration. Autoload from absolute path, invoke once,
# unfunction. The script has its own `$+_ghostty_state` guard so a second
# load is a no-op.
if [[ -o interactive ]] && [ -n "$IN0_AGENT_HOOKS_DIR" ]; then
    _in0_ghostty_zsh="${IN0_AGENT_HOOKS_DIR%/agent-hooks}/ghostty/shell-integration/zsh/ghostty-integration"
    if [ -r "$_in0_ghostty_zsh" ]; then
        autoload -Uz -- "$_in0_ghostty_zsh"
        ghostty-integration
        unfunction ghostty-integration 2>/dev/null
    fi
    unset _in0_ghostty_zsh
fi

# ── 4. Defer bootstrap to first prompt ─────────────────────────────────
if [[ -o interactive ]] && [ -n "$IN0_AGENT_HOOKS_DIR" ]; then
    autoload -Uz add-zsh-hook 2>/dev/null

    _in0_bootstrap_first_prompt() {
        if [ -f "$IN0_AGENT_HOOKS_DIR/bootstrap.zsh" ]; then
            source "$IN0_AGENT_HOOKS_DIR/bootstrap.zsh"
        fi
        add-zsh-hook -d precmd _in0_bootstrap_first_prompt 2>/dev/null
        unfunction _in0_bootstrap_first_prompt 2>/dev/null
    }

    if (( $+functions[add-zsh-hook] )); then
        add-zsh-hook precmd _in0_bootstrap_first_prompt
    fi
fi
