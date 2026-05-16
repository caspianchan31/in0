import XCTest
@testable import in0

final class TerminalStatusTests: XCTestCase {

    func testNeverRanIsDefault() {
        XCTAssertEqual(TerminalStatus.neverRan, .neverRan)
    }

    func testRunningEqualityIsStrictAboutTimestamps() {
        let a = Date(timeIntervalSince1970: 1000)
        let b = Date(timeIntervalSince1970: 2000)
        XCTAssertNotEqual(
            TerminalStatus.running(startedAt: a),
            TerminalStatus.running(startedAt: b)
        )
    }

    func testAggregateEmptyIsNeverRan() {
        XCTAssertEqual(TerminalStatus.aggregate([]), .neverRan)
    }

    func testAggregateAllNeverRan() {
        XCTAssertEqual(TerminalStatus.aggregate([.neverRan, .neverRan]), .neverRan)
    }

    func testRunningBeatsEverythingButNeedsInput() {
        let now = Date()
        let inputs: [TerminalStatus] = [
            .success(exitCode: 0, duration: 1, finishedAt: now, agent: .claude),
            .failed(exitCode: 1, duration: 2, finishedAt: now, agent: .claude),
            .running(startedAt: now),
            .neverRan,
        ]
        XCTAssertEqual(TerminalStatus.aggregate(inputs).caseName, "running")
    }

    func testFailedBeatsSuccess() {
        let now = Date()
        let inputs: [TerminalStatus] = [
            .success(exitCode: 0, duration: 1, finishedAt: now, agent: .claude),
            .failed(exitCode: 2, duration: 3, finishedAt: now, agent: .claude),
            .neverRan,
        ]
        XCTAssertEqual(TerminalStatus.aggregate(inputs).caseName, "failed")
    }

    func testIdleBeatsNeverRanLosesToSuccess() {
        let now = Date()
        XCTAssertEqual(
            TerminalStatus.aggregate([.idle(since: now), .neverRan]).caseName, "idle"
        )
        XCTAssertEqual(
            TerminalStatus.aggregate([
                .success(exitCode: 0, duration: 1, finishedAt: now, agent: .claude),
                .idle(since: now)
            ]).caseName, "success"
        )
    }

    func testNeedsInputWinsOverAll() {
        let now = Date()
        let inputs: [TerminalStatus] = [
            .running(startedAt: now),
            .failed(exitCode: 1, duration: 1, finishedAt: now, agent: .claude),
            .success(exitCode: 0, duration: 1, finishedAt: now, agent: .claude),
            .needsInput(since: now),
            .idle(since: now),
            .neverRan
        ]
        XCTAssertEqual(TerminalStatus.aggregate(inputs).caseName, "needsInput")
    }

    func testFullPriorityChain() {
        let now = Date()
        let ordered: [(TerminalStatus, String)] = [
            (.needsInput(since: now), "needsInput"),
            (.running(startedAt: now), "running"),
            (.failed(exitCode: 1, duration: 1, finishedAt: now, agent: .claude), "failed"),
            (.success(exitCode: 0, duration: 1, finishedAt: now, agent: .claude), "success"),
            (.idle(since: now), "idle"),
            (.neverRan, "neverRan"),
        ]
        for (i, (high, expected)) in ordered.enumerated() {
            for j in (i + 1) ..< ordered.count {
                let low = ordered[j].0
                XCTAssertEqual(
                    TerminalStatus.aggregate([low, high]).caseName, expected,
                    "\(expected) should beat \(ordered[j].1)"
                )
            }
        }
    }

    func testReadStateBeatsUnreadAtSamePriority() {
        let now = Date()
        let read = TerminalStatus.success(
            exitCode: 0, duration: 1, finishedAt: now, agent: .claude,
            summary: nil, readAt: Date()
        )
        let unread = TerminalStatus.success(
            exitCode: 0, duration: 1, finishedAt: now, agent: .claude
        )
        // aggregate must prefer the unread one so a fresh result pulls focus.
        XCTAssertFalse(TerminalStatus.aggregate([read, unread]).isRead)
    }
}
