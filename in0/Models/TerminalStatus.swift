import Foundation

/// Lifecycle state of a single terminal — driven by hook events from
/// AI agents (Claude Code / Codex / OpenCode).
///
/// The richer constructors (timestamps, duration, agent, summary, readAt)
/// exist so the status icon can show "running for 12s", the tooltip can
/// quote the last assistant message, and the sidebar dot can flip to
/// "read" once the user has acknowledged the result. State lives entirely
/// in-memory — restart resets every terminal to `.neverRan`.
enum TerminalStatus: Equatable, Sendable {
    case neverRan
    case running(startedAt: Date, detail: String? = nil)
    case idle(since: Date)
    case needsInput(since: Date)
    /// Last turn finished cleanly (every PostToolUse hook reported success).
    case success(exitCode: Int32, duration: TimeInterval, finishedAt: Date,
                 agent: HookAgent, summary: String? = nil,
                 readAt: Date? = nil)
    /// Last turn finished with at least one tool error. We still surface
    /// the summary; the dot just colors red instead of green.
    case failed(exitCode: Int32, duration: TimeInterval, finishedAt: Date,
                agent: HookAgent, summary: String? = nil,
                readAt: Date? = nil)

    /// Aggregation priority. `needsInput` wins everything; `failed` wins
    /// over `success` so an attention-needed badge doesn't get hidden by
    /// a more recent green dot.
    var priority: Int {
        switch self {
        case .needsInput: return 5
        case .running:    return 4
        case .failed:     return 3
        case .success:    return 2
        case .idle:       return 1
        case .neverRan:   return 0
        }
    }

    /// Reduce many statuses to one aggregate. Ties prefer "unread" so a
    /// fresh failed pulls focus over a previously-acknowledged failed.
    /// Empty input → `.neverRan`.
    static func aggregate(_ statuses: [TerminalStatus]) -> TerminalStatus {
        statuses.reduce(TerminalStatus.neverRan) { current, next in
            if next.priority > current.priority { return next }
            if next.priority == current.priority, current.isRead, !next.isRead { return next }
            return current
        }
    }

    /// Stringified case name. Exists purely so tests can compare cases
    /// without writing out switch ladders. Production code should pattern
    /// match instead.
    var caseName: String {
        switch self {
        case .neverRan:   return "neverRan"
        case .running:    return "running"
        case .idle:       return "idle"
        case .needsInput: return "needsInput"
        case .success:    return "success"
        case .failed:     return "failed"
        }
    }

    /// True once the user has dismissed / acknowledged this status. Only
    /// `success` / `failed` carry a readAt; other kinds always return false.
    var isRead: Bool {
        switch self {
        case .success(_, _, _, _, _, let readAt): return readAt != nil
        case .failed(_, _, _, _, _, let readAt):  return readAt != nil
        default: return false
        }
    }
}

enum HookAgent: String, Codable, Sendable, Equatable, CaseIterable {
    case claude
    case codex
    case opencode

    /// User-visible name for tooltips / settings rows.
    var displayName: String {
        switch self {
        case .claude:   return "Claude"
        case .codex:    return "Codex"
        case .opencode: return "OpenCode"
        }
    }

    /// Identify which agent a `<agent> --resume <id>`-style command line
    /// refers to. Used by `StartupCommandResolver` to gate resume replays
    /// — only the matching agent's Resume toggle should re-enable a
    /// stored prefill.
    static func fromResumeCommand(_ command: String) -> HookAgent? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" }).first else { return nil }
        return HookAgent(rawValue: String(first))
    }
}
