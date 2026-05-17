import XCTest
import AppKit
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

    func testTerminalClipboardPayloadWritesImagePasteboardToPath() throws {
        let pasteboard = NSPasteboard(name: .init("in0.image-payload.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.declareTypes([.tiff], owner: nil)
        try pasteboard.setTestImage()

        let payload = try XCTUnwrap(TerminalClipboardPayload.payload(from: pasteboard))
        let path = unquotedPath(from: payload)

        XCTAssertTrue(path.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testTerminalClipboardPayloadPrefersImageOverFallbackText() throws {
        let pasteboard = NSPasteboard(name: .init("in0.image-over-text.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.declareTypes([.string, .tiff], owner: nil)
        pasteboard.setString("fallback text", forType: .string)
        try pasteboard.setTestImage()

        let payload = try XCTUnwrap(TerminalClipboardPayload.payload(from: pasteboard))

        XCTAssertNotEqual(payload, "fallback text")
        XCTAssertTrue(unquotedPath(from: payload).hasSuffix(".png"))
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

    private func unquotedPath(from payload: String) -> String {
        payload
            .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            .replacingOccurrences(of: "'\\''", with: "'")
    }
}

private extension NSPasteboard {
    func setTestImage() throws {
        let image = NSImage(size: NSSize(width: 2, height: 2))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        image.unlockFocus()

        let data = try XCTUnwrap(image.tiffRepresentation)
        setData(data, forType: .tiff)
    }
}
