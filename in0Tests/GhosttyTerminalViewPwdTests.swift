import XCTest
@testable import in0

/// `GhosttyTerminalView.validatedDirectory` is the safety check that
/// keeps libghostty from SIGSEGV'ing when we pass an inherited pwd that
/// no longer exists (e.g. user closed a tab, removed the dir, then
/// reopened a workspace whose split inherited that pwd).
@MainActor
final class GhosttyTerminalViewPwdTests: XCTestCase {

    func testNilInputReturnsNil() {
        XCTAssertNil(GhosttyTerminalView.validatedDirectory(nil))
    }

    func testExistingDirectoryRoundTrips() {
        // /tmp exists on every macOS host and is always a directory.
        XCTAssertEqual(GhosttyTerminalView.validatedDirectory("/tmp"), "/tmp")
    }

    func testNonexistentPathReturnsNil() {
        let fake = "/nonexistent/\(UUID().uuidString)"
        XCTAssertNil(GhosttyTerminalView.validatedDirectory(fake))
    }

    func testRegularFileRejected() {
        let dir = NSTemporaryDirectory()
        let path = (dir as NSString).appendingPathComponent("in0-test-\(UUID()).txt")
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }
        XCTAssertNil(GhosttyTerminalView.validatedDirectory(path))
    }

    func testMarkedTextTracksImeCompositionState() {
        let view = GhosttyTerminalView(terminalId: UUID())

        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 2))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 0))

        view.unmarkText()

        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: NSNotFound, length: 0))
        XCTAssertEqual(view.selectedRange(), NSRange(location: NSNotFound, length: 0))
    }

    func testCommittedTextClearsMarkedCompositionWithoutSurface() {
        let view = GhosttyTerminalView(terminalId: UUID())
        view.setMarkedText(NSAttributedString(string: "zhong"), selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

        view.insertText("中", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(view.selectedRange(), NSRange(location: NSNotFound, length: 0))
    }

    func testControlModifiedKeysForwardToTerminal() {
        XCTAssertTrue(GhosttyTerminalView.shouldForwardModifiedKeyToTerminal(modifierFlags: [.control]))
        XCTAssertTrue(GhosttyTerminalView.shouldForwardModifiedKeyToTerminal(modifierFlags: [.control, .shift]))
    }

    func testCommandShortcutsStayOnResponderChain() {
        XCTAssertFalse(GhosttyTerminalView.shouldForwardModifiedKeyToTerminal(modifierFlags: [.command]))
        XCTAssertFalse(GhosttyTerminalView.shouldForwardModifiedKeyToTerminal(modifierFlags: [.command, .control]))
    }
}
