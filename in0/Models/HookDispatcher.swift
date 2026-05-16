import Foundation

/// Translates a decoded `HookMessage` into a `TerminalStatus` mutation,
/// applying agent-level toggles for notifications + resume command
/// recording.
///
/// Status timestamps use `HookMessage.at` when present (the hook script's
/// `$EPOCHREALTIME` capture, which orders correctly even when two `&!`
/// processes race); otherwise we fall back to `Date()` (the dispatcher's
/// own wall clock). Duration on success/failed is computed by looking up
/// the most recent `running`'s `startedAt` for the same terminal.
@MainActor
final class HookDispatcher {
    private let store: TerminalStatusStore
    private let settings: SettingsStore

    init(store: TerminalStatusStore, settings: SettingsStore) {
        self.store = store
        self.settings = settings
    }

    func handle(_ msg: HookMessage) {
        let prefs = settings.prefs(for: msg.agent)
        if prefs.resumeOnLaunch, let resume = msg.resumeCommand, !resume.isEmpty {
            ResumeStore.shared.record(terminalId: msg.terminalId, command: resume)
        }
        if msg.event == .needsInput && !prefs.notificationsEnabled {
            // Claude's Notification hook doubles as a 60s heartbeat. Honor
            // the agent's toggle so users can suppress that noise without
            // losing real running/idle/finished events.
            return
        }

        let now: Date = msg.at.map { Date(timeIntervalSince1970: $0) } ?? Date()

        switch msg.event {
        case .running:
            let startedAt: Date
            if case .running(let existing, _) = store.status(for: msg.terminalId) {
                startedAt = existing
            } else {
                startedAt = now
            }
            store.setStatus(
                .running(startedAt: startedAt, detail: msg.toolDetail),
                for: msg.terminalId,
                agent: msg.agent
            )
        case .idle:
            store.setStatus(.idle(since: now), for: msg.terminalId, agent: msg.agent)
        case .needsInput:
            store.applyNeedsInputGated(since: now, for: msg.terminalId, agent: msg.agent)
        case .finished:
            let exit = Int32(msg.exitCode ?? 0)
            let started = startedAt(for: msg.terminalId) ?? now
            let duration = max(0, now.timeIntervalSince(started))
            let status: TerminalStatus = exit == 0
                ? .success(exitCode: exit, duration: duration, finishedAt: now,
                           agent: msg.agent, summary: msg.summary)
                : .failed(exitCode: exit, duration: duration, finishedAt: now,
                          agent: msg.agent, summary: msg.summary)
            store.setStatus(status, for: msg.terminalId, agent: msg.agent)
        }
    }

    private func startedAt(for terminalId: UUID) -> Date? {
        if case .running(let started, _) = store.status(for: terminalId) {
            return started
        }
        return nil
    }
}
