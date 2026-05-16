import Foundation

/// Wire format for status updates pushed by an agent's hook script over a
/// Unix socket. One JSON object per line. Each field is optional except
/// `terminalId`, `event`, and `agent` so older hook versions remain
/// forward-compatible.
struct HookMessage: Codable, Equatable {
    enum Event: String, Codable {
        case running
        case idle
        case needsInput
        case finished
    }

    var terminalId: UUID
    var event: Event
    var agent: HookAgent
    var at: TimeInterval?
    var exitCode: Int?
    var toolDetail: String?
    var summary: String?
    var resumeCommand: String?

    static func decode(line: String) -> HookMessage? {
        guard let data = line.data(using: .utf8) else { return nil }
        let dec = JSONDecoder()
        return try? dec.decode(HookMessage.self, from: data)
    }
}
