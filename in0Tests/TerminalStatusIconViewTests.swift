import AppKit
import XCTest
@testable import in0

@MainActor
final class TerminalStatusIconViewTests: XCTestCase {

    func testNeverRanRendersAsHollowOutline() {
        let style = TerminalStatusIconView.renderStyle(for: .neverRan, theme: .darkDefault)
        XCTAssertNotNil(style)
        XCTAssertEqual(style?.fill, .clear)
        XCTAssertGreaterThan(style?.lineWidth ?? 0, 0)
    }

    func testRunningHasNoFillStyle() {
        // running paints a custom 270° arc path; renderStyle returns nil
        // for that kind because the ellipse style record doesn't apply.
        let style = TerminalStatusIconView.renderStyle(
            for: .running(startedAt: Date()), theme: .darkDefault
        )
        XCTAssertNil(style)
    }

    func testNeedsInputIsFilledAccent() {
        let style = TerminalStatusIconView.renderStyle(
            for: .needsInput(since: Date()), theme: .darkDefault
        )
        XCTAssertEqual(style?.lineWidth, 0)
        XCTAssertNotNil(style?.fill)
    }

    func testFailedUnreadIsDangerFill() {
        let style = TerminalStatusIconView.renderStyle(
            for: .failed(exitCode: 1, duration: 1, finishedAt: Date(), agent: .claude),
            theme: .darkDefault
        )
        XCTAssertEqual(style?.lineWidth, 0)
        // Filled (no stroke). Exact color matching depends on theme; we
        // only assert the color isn't clear.
        XCTAssertNotEqual(style?.fill, .clear)
    }

    func testFailedReadCollapsesToOutline() {
        let style = TerminalStatusIconView.renderStyle(
            for: .failed(
                exitCode: 1, duration: 1, finishedAt: Date(),
                agent: .claude, summary: nil, readAt: Date()
            ),
            theme: .darkDefault
        )
        XCTAssertEqual(style?.fill, .clear)
        XCTAssertGreaterThan(style?.lineWidth ?? 0, 0)
    }

    func testTooltipMentionsAgentForSuccess() {
        let text = TerminalStatusIconView.tooltip(for:
            .success(exitCode: 0, duration: 5, finishedAt: Date(), agent: .codex, summary: "ok")
        )
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains("Codex") ?? false)
    }

    func testTooltipForNeverRanIsNil() {
        XCTAssertNil(TerminalStatusIconView.tooltip(for: .neverRan))
    }
}
