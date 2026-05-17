import XCTest
@testable import in0

@MainActor
final class TerminalSearchStoreTests: XCTestCase {
    func testOpenUpdateAndCloseSearchState() {
        let store = TerminalSearchStore()
        let terminalId = UUID()

        store.open(for: terminalId)
        XCTAssertTrue(store.isPresented)
        XCTAssertEqual(store.terminalId, terminalId)

        store.updateQuery("build")
        XCTAssertEqual(store.query, "build")
        XCTAssertNil(store.total)
        XCTAssertNil(store.selected)

        store.applyTotal(3, terminalId: terminalId)
        store.applySelected(1, terminalId: terminalId)
        XCTAssertEqual(store.total, 3)
        XCTAssertEqual(store.selected, 2)

        store.close()
        XCTAssertFalse(store.isPresented)
        XCTAssertNil(store.terminalId)
        XCTAssertEqual(store.query, "")
        XCTAssertNil(store.total)
        XCTAssertNil(store.selected)
    }

    func testIgnoresResultCallbacksFromOtherTerminal() {
        let store = TerminalSearchStore()
        let focused = UUID()

        store.open(for: focused)
        store.applyTotal(7, terminalId: UUID())
        store.applySelected(2, terminalId: UUID())

        XCTAssertNil(store.total)
        XCTAssertNil(store.selected)
    }
}
