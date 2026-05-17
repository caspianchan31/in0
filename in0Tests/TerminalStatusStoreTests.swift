import XCTest
@testable import in0

@MainActor
final class TerminalStatusStoreTests: XCTestCase {

    func testDefaultStatusIsNeverRan() {
        let store = TerminalStatusStore()
        XCTAssertEqual(store.status(for: UUID()), .neverRan)
    }

    func testSetStatusUpdates() {
        let store = TerminalStatusStore()
        let id = UUID()
        let now = Date()
        store.setStatus(.running(startedAt: now, detail: "Edit Foo.swift"),
                        for: id, agent: .claude)
        XCTAssertEqual(store.status(for: id), .running(startedAt: now, detail: "Edit Foo.swift"))
        XCTAssertEqual(store.agents[id], .claude)
    }

    func testSetStatusCanUpdateAgentWhenStatusIsUnchanged() {
        let store = TerminalStatusStore()
        let id = UUID()
        let now = Date()
        let status = TerminalStatus.running(startedAt: now, detail: "Edit Foo.swift")

        store.setStatus(status, for: id, agent: .claude)
        store.setStatus(status, for: id, agent: .codex)

        XCTAssertEqual(store.status(for: id), status)
        XCTAssertEqual(store.agents[id], .codex)
    }

    func testNeedsInputGateRequiresRunning() {
        let store = TerminalStatusStore()
        let id = UUID()
        // Without a prior running, the gate drops the message.
        store.applyNeedsInputGated(since: Date(), for: id, agent: .claude)
        XCTAssertEqual(store.status(for: id), .neverRan)
    }

    func testNeedsInputGateAppliesWhenRunning() {
        let store = TerminalStatusStore()
        let id = UUID()
        store.setStatus(.running(startedAt: Date()), for: id, agent: .claude)
        store.applyNeedsInputGated(since: Date(), for: id, agent: .claude)
        if case .needsInput = store.status(for: id) {} else {
            XCTFail("expected needsInput after running gate")
        }
    }

    func testAggregateOverIds() {
        let store = TerminalStatusStore()
        let a = UUID(); let b = UUID(); let c = UUID()
        store.setStatus(.idle(since: Date()), for: a)
        store.setStatus(.running(startedAt: Date()), for: b)
        store.setStatus(.success(exitCode: 0, duration: 1, finishedAt: Date(), agent: .claude), for: c)
        XCTAssertEqual(store.aggregate(over: [a, b, c]).caseName, "running")
    }

    func testMarkReadOnlyAffectsFinished() {
        let store = TerminalStatusStore()
        let id = UUID()
        store.setStatus(
            .success(exitCode: 0, duration: 1, finishedAt: Date(), agent: .claude),
            for: id
        )
        XCTAssertFalse(store.status(for: id).isRead)
        store.markRead(id)
        XCTAssertTrue(store.status(for: id).isRead)

        // markRead on an idle status is a no-op
        let other = UUID()
        store.setStatus(.idle(since: Date()), for: other)
        store.markRead(other)
        XCTAssertEqual(store.status(for: other).caseName, "idle")
    }

    func testMarkReadIsIdempotent() {
        let store = TerminalStatusStore()
        let id = UUID()
        let finishedAt = Date(timeIntervalSince1970: 10)
        let firstRead = Date(timeIntervalSince1970: 20)
        let secondRead = Date(timeIntervalSince1970: 30)
        store.setStatus(
            .success(exitCode: 0, duration: 1, finishedAt: finishedAt, agent: .claude),
            for: id
        )

        store.markRead(id, at: firstRead)
        store.markRead(id, at: secondRead)

        XCTAssertEqual(
            store.status(for: id),
            .success(
                exitCode: 0,
                duration: 1,
                finishedAt: finishedAt,
                agent: .claude,
                readAt: firstRead
            )
        )
    }

    func testRemoveClearsStatusAndAgent() {
        let store = TerminalStatusStore()
        let id = UUID()
        store.setStatus(.idle(since: Date()), for: id, agent: .codex)
        store.remove(id)
        XCTAssertEqual(store.status(for: id), .neverRan)
        XCTAssertNil(store.agents[id])
    }
}
