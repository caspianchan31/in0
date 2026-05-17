import Foundation
import Observation

@MainActor
@Observable
final class TerminalStatusStore {
    private(set) var statuses: [UUID: TerminalStatus] = [:]
    private(set) var agents: [UUID: HookAgent] = [:]

    func status(for terminalId: UUID) -> TerminalStatus {
        statuses[terminalId] ?? .neverRan
    }

    func setStatus(_ status: TerminalStatus, for terminalId: UUID, agent: HookAgent? = nil) {
        if statuses[terminalId] == status,
           agent == nil || agents[terminalId] == agent {
            return
        }
        statuses[terminalId] = status
        if let agent { agents[terminalId] = agent }
    }

    /// `needsInput` only lands when we're already running. Claude's
    /// `Notification` hook doubles as a 60s idle heartbeat, so an
    /// unconditional set would clobber a `.finished` state every minute.
    func applyNeedsInputGated(since: Date, for terminalId: UUID, agent: HookAgent) {
        if case .running = status(for: terminalId) {
            setStatus(.needsInput(since: since), for: terminalId, agent: agent)
        }
    }

    /// Workspace-level rollup: highest-priority status across the listed
    /// terminals. Ties prefer unread so an old un-acknowledged failure
    /// outranks a more recent acknowledged one.
    func aggregate(over terminalIds: [UUID]) -> TerminalStatus {
        TerminalStatus.aggregate(terminalIds.map { status(for: $0) })
    }

    /// Mark a finished status as read. Idempotent. No-op on other kinds.
    func markRead(_ terminalId: UUID, at: Date = Date()) {
        guard let current = statuses[terminalId] else { return }
        switch current {
        case .success(_, _, _, _, _, let readAt) where readAt != nil:
            return
        case .success(let ec, let dur, let fin, let agent, let summary, _):
            statuses[terminalId] = .success(
                exitCode: ec, duration: dur, finishedAt: fin,
                agent: agent, summary: summary, readAt: at
            )
        case .failed(_, _, _, _, _, let readAt) where readAt != nil:
            return
        case .failed(let ec, let dur, let fin, let agent, let summary, _):
            statuses[terminalId] = .failed(
                exitCode: ec, duration: dur, finishedAt: fin,
                agent: agent, summary: summary, readAt: at
            )
        default:
            break
        }
    }

    func remove(_ terminalId: UUID) {
        statuses.removeValue(forKey: terminalId)
        agents.removeValue(forKey: terminalId)
    }
}
