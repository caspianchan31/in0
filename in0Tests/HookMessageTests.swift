import XCTest
@testable import in0

final class HookMessageTests: XCTestCase {

    private let baseTerminalId = "550E8400-E29B-41D4-A716-446655440000"

    func testDecodeRunning() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"running","agent":"claude","at":1713345678.5}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertEqual(msg.terminalId, UUID(uuidString: baseTerminalId))
        XCTAssertEqual(msg.event, .running)
        XCTAssertEqual(msg.agent, .claude)
    }

    func testDecodeUnknownAgentFails() {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"idle","agent":"cursor","at":1}"#
            .data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(HookMessage.self, from: json))
    }

    func testDecodeShellAgentFails() {
        // `shell` is a sentinel used by the bash emitter when there's no
        // agent context; it shouldn't decode into the typed `HookAgent`.
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"idle","agent":"shell","at":1}"#
            .data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(HookMessage.self, from: json))
    }

    func testDecodeNeedsInput() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"needsInput","agent":"opencode","at":2}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertEqual(msg.event, .needsInput)
    }

    func testDecodeIgnoresUnknownTopLevelFields() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"running","agent":"codex","at":1,"meta":{"tool":"shell"}}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertEqual(msg.agent, .codex)
    }

    func testDecodeIdleHasNoExitCode() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"idle","agent":"claude","at":1}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertEqual(msg.event, .idle)
        XCTAssertNil(msg.exitCode)
    }

    func testDecodeRunningWithToolDetail() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"running","agent":"claude","at":1713500000.0,"toolDetail":"Edit Models/Foo.swift"}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertEqual(msg.toolDetail, "Edit Models/Foo.swift")
        XCTAssertNil(msg.summary)
        XCTAssertNil(msg.exitCode)
    }

    func testDecodeFinishedCarriesExitCodeAndSummary() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"finished","agent":"claude","at":1713500015.3,"exitCode":0,"summary":"Refactored WorkspaceStore."}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertEqual(msg.event, .finished)
        XCTAssertEqual(msg.exitCode, 0)
        XCTAssertEqual(msg.summary, "Refactored WorkspaceStore.")
        XCTAssertNil(msg.toolDetail)
    }

    func testAgentAllCasesExcludesShell() {
        XCTAssertEqual(HookAgent.allCases.count, 3)
        XCTAssertEqual(Set(HookAgent.allCases.map(\.rawValue)),
                       Set(["claude", "codex", "opencode"]))
    }

    func testDecodeRunningWithResumeCommand() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"running","agent":"claude","at":1713500000,"resumeCommand":"claude --resume abc-123"}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertEqual(msg.resumeCommand, "claude --resume abc-123")
    }

    func testDecodeMessageWithoutResumeIsNil() throws {
        let json = #"{"terminalId":"\#(baseTerminalId)","event":"running","agent":"claude","at":1}"#
            .data(using: .utf8)!
        let msg = try JSONDecoder().decode(HookMessage.self, from: json)
        XCTAssertNil(msg.resumeCommand)
    }

    func testFromResumeCommandRecognizesAgents() {
        XCTAssertEqual(HookAgent.fromResumeCommand("claude --resume abc"),  .claude)
        XCTAssertEqual(HookAgent.fromResumeCommand("codex resume xyz"),     .codex)
        XCTAssertEqual(HookAgent.fromResumeCommand("opencode --session z"), .opencode)
        XCTAssertNil(HookAgent.fromResumeCommand("random thing"))
        XCTAssertNil(HookAgent.fromResumeCommand(""))
    }
}
