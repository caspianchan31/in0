import Foundation

/// One-shot command queue keyed by terminal id. Quick Actions enqueue
/// a launcher command when a new tab is opened; the terminal view drains
/// the entry once its ghostty surface is online.
@MainActor
final class TerminalCommandQueue {
    static let shared = TerminalCommandQueue()
    private var pending: [UUID: String] = [:]

    private init() {}

    func enqueue(_ command: String, for terminalId: UUID) {
        pending[terminalId] = command
    }

    func drain(for terminalId: UUID) -> String? {
        pending.removeValue(forKey: terminalId)
    }
}
