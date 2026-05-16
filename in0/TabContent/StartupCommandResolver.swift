import Foundation

/// Pure resolver for the shell command that should be auto-injected when a
/// fresh ghostty surface comes online. Pulled out of the view layer so the
/// precedence rules are unit-testable without an NSView, a WorkspaceStore,
/// or any singletons.
///
/// **Source order**:
///   0. **Quick-action tab, first terminal**:
///      0a. If the action id matches a builtin agent (`claude` / `codex` /
///          `opencode`), the agent's Resume toggle is on, AND
///          `pendingPrefill` is a `<agent> --resume <id>`-style command for
///          the **same** agent → return the prefill verbatim. The agent
///          equality guard prevents a stored prefill from one agent being
///          replayed under another's button. User overrides of the builtin
///          command (e.g. `claude --debug`) are intentionally bypassed:
///          enabling Resume on Claude implies "continue the prior session"
///          regardless of debug flags.
///      0b. Otherwise → return `quickActionCommand` + newline.
///   1. **Plain terminal, agent resume**: `pendingPrefill` looks like a
///      resume command AND the matching agent's Resume toggle is on.
///      Default OFF means stale entries are NOT replayed silently.
///   2. **Workspace default command** (fall-through).
///
/// All inputs are passed explicitly so the resolver stays pure.
enum StartupCommandResolver {
    static func resolve(
        terminalId: UUID,
        tab: TerminalTab?,
        workspaceDefaultCommand: String?,
        quickActionCommand: (QuickActionId) -> String?,
        isResumeEnabled: (HookAgent) -> Bool,
        pendingPrefill: String?
    ) -> String? {
        // (0) Tab launched from a Quick Action click — first terminal only.
        if let tab,
           let actionId = tab.quickActionId,
           terminalId == tab.layout.allTerminalIds().first {

            // (0a) Builtin agent + matching prefill + Resume on → replay.
            if let agent = HookAgent(rawValue: actionId),
               isResumeEnabled(agent),
               let prefill = pendingPrefill,
               HookAgent.fromResumeCommand(prefill) == agent {
                return prefill
            }
            // (0b) Otherwise honor the action's own command.
            if let cmd = quickActionCommand(actionId) {
                return "\(cmd)\n"
            }
        }

        // (1) Plain terminal — agent resume path.
        if let prefill = pendingPrefill,
           let agent = HookAgent.fromResumeCommand(prefill),
           isResumeEnabled(agent) {
            return prefill
        }

        // (2) Workspace default.
        return workspaceDefaultCommand
    }
}
