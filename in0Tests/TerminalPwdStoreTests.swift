import XCTest
@testable import in0

@MainActor
final class TerminalPwdStoreTests: XCTestCase {

    func testDefaultIsEmpty() {
        let store = TerminalPwdStore(persistenceKey: "test-\(UUID())")
        XCTAssertNil(store.pwd(for: UUID()))
    }

    func testSetPwdRoundTripsThroughSaveAndReload() {
        let key = "test-\(UUID())"
        let id = UUID()
        let a = TerminalPwdStore(persistenceKey: key)
        a.setPwd("/tmp/foo", for: id)
        a.flushSaveForTesting()

        let b = TerminalPwdStore(persistenceKey: key)
        XCTAssertEqual(b.pwd(for: id), "/tmp/foo")
        UserDefaults.standard.removeObject(forKey: key)
    }

    func testDebouncedSavePersists() {
        let key = "test-\(UUID())"
        let id = UUID()
        let store = TerminalPwdStore(persistenceKey: key)
        store.setPwd("/tmp/debounce-test", for: id)

        let exp = expectation(description: "debounce flush")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        let second = TerminalPwdStore(persistenceKey: key)
        XCTAssertEqual(second.pwd(for: id), "/tmp/debounce-test")
        UserDefaults.standard.removeObject(forKey: key)
        _ = store  // keep the original alive across the debounce wait
    }

    func testInheritCopiesPwd() {
        let store = TerminalPwdStore(persistenceKey: "test-\(UUID())")
        let src = UUID(); let dst = UUID()
        store.setPwd("/tmp/bar", for: src)
        store.inherit(from: src, to: dst)
        XCTAssertEqual(store.pwd(for: dst), "/tmp/bar")
    }

    func testInheritWithoutSourceIsNoop() {
        let store = TerminalPwdStore(persistenceKey: "test-\(UUID())")
        store.inherit(from: UUID(), to: UUID())
        XCTAssertNil(store.pwd(for: UUID()))
    }

    func testForgetRemovesEntry() {
        let store = TerminalPwdStore(persistenceKey: "test-\(UUID())")
        let id = UUID()
        store.setPwd("/tmp/baz", for: id)
        store.forget(terminalId: id)
        XCTAssertNil(store.pwd(for: id))
    }

    func testPwdsSnapshotReturnsCurrentMap() {
        let store = TerminalPwdStore(persistenceKey: "test-\(UUID())")
        let a = UUID(); let b = UUID()
        store.setPwd("/tmp/a", for: a)
        store.setPwd("/tmp/b", for: b)
        let snap = store.pwdsSnapshot()
        XCTAssertEqual(snap.count, 2)
        XCTAssertEqual(snap[a], "/tmp/a")
        XCTAssertEqual(snap[b], "/tmp/b")
    }
}
