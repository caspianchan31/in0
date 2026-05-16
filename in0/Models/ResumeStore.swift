import Foundation
import Observation

/// Persists the most recent `<agent> --resume <session>` command per terminal,
/// reported via the agent hook protocol. On next app launch, when a surface
/// comes online, the terminal view drains the stored command and re-runs it,
/// reattaching to the prior agent session.
@MainActor
@Observable
final class ResumeStore {
    static let shared = ResumeStore()

    private static let storageKey = "in0.resumeCommands.v1"
    private var commands: [String: String]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            self.commands = decoded
        } else {
            self.commands = [:]
        }
    }

    func record(terminalId: UUID, command: String) {
        commands[terminalId.uuidString] = command
        persist()
    }

    func clear(terminalId: UUID) {
        commands.removeValue(forKey: terminalId.uuidString)
        persist()
    }

    func clearCommands(for agent: HookAgent) {
        commands = commands.filter { HookAgent.fromResumeCommand($0.value) != agent }
        persist()
    }

    /// Look up the resume command without removing it. Used by the
    /// StartupCommandResolver during its decision phase; the consume call
    /// happens later, only if the resolver actually chose to replay it
    /// (otherwise a stale prefill would silently disappear when the user
    /// has the agent's Resume toggle OFF).
    func peek(terminalId: UUID) -> String? {
        commands[terminalId.uuidString]
    }

    /// Consume and return the resume command for `terminalId`, removing it.
    func consume(terminalId: UUID) -> String? {
        let id = terminalId.uuidString
        guard let cmd = commands.removeValue(forKey: id) else { return nil }
        persist()
        return cmd
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(commands) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
