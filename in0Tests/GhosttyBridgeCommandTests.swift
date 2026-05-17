import XCTest
@testable import in0

/// `WorkspaceDefaultCommand.startupInput(for:)` is the small pure helper
/// that decides what (if anything) to type into a fresh shell on behalf
/// of the user. It's split out so trim + trailing-newline rules stay in
/// one place, and so the resolver and any future direct caller agree on
/// "this is empty, don't send anything".
final class GhosttyBridgeCommandTests: XCTestCase {
    func testStartupInputTrimsAndAppendsNewline() {
        XCTAssertEqual(WorkspaceDefaultCommand.startupInput(for: "  claude  "), "claude")
    }

    func testStartupInputReturnsNilForEmptyOrNil() {
        XCTAssertNil(WorkspaceDefaultCommand.startupInput(for: nil))
        XCTAssertNil(WorkspaceDefaultCommand.startupInput(for: ""))
        XCTAssertNil(WorkspaceDefaultCommand.startupInput(for: "   \n  "))
    }

    func testTerminalClipboardPayloadShellQuotesImagePaths() {
        XCTAssertEqual(
            TerminalClipboardPayload.shellQuotedPath("/tmp/a folder/it's.png"),
            "'/tmp/a folder/it'\\''s.png'"
        )
    }

    @MainActor
    func testTerminalCommandQueueStoresExecutableInput() {
        let terminalId = UUID()
        TerminalCommandQueue.shared.enqueue("  gitui  ", for: terminalId)
        XCTAssertEqual(TerminalCommandQueue.shared.drain(for: terminalId), "gitui")
        XCTAssertNil(TerminalCommandQueue.shared.drain(for: terminalId))
    }

    @MainActor
    func testTerminalCommandQueueRejectsEmptyInput() {
        let terminalId = UUID()
        TerminalCommandQueue.shared.enqueue("   ", for: terminalId)
        XCTAssertNil(TerminalCommandQueue.shared.drain(for: terminalId))
    }
}
