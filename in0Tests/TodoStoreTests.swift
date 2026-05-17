import XCTest
@testable import in0

@MainActor
final class TodoStoreTests: XCTestCase {
    private var tmpURL: URL!

    override func setUp() {
        super.setUp()
        tmpURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("in0-todo-tests-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpURL)
        tmpURL = nil
        super.tearDown()
    }

    func testAddToggleAndPersistByWorkspace() {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let store = TodoStore(fileURL: tmpURL)

        let item = store.add(title: "  Review cards  ", workspaceId: workspaceA)!
        _ = store.add(title: "Other workspace", workspaceId: workspaceB)
        store.setDone(item.id, true)

        let reload = TodoStore(fileURL: tmpURL)

        XCTAssertEqual(reload.items(for: workspaceA).map(\.title), ["Review cards"])
        XCTAssertTrue(reload.items(for: workspaceA)[0].isDone)
        XCTAssertEqual(reload.items(for: workspaceB).map(\.title), ["Other workspace"])
    }

    func testRejectsEmptyTitlesAndCanClearDone() {
        let workspace = UUID()
        let store = TodoStore(fileURL: tmpURL)

        XCTAssertNil(store.add(title: "   ", workspaceId: workspace))
        let open = store.add(title: "Open", workspaceId: workspace)!
        let done = store.add(title: "Done", workspaceId: workspace)!
        store.setDone(done.id, true)
        store.clearDone(in: workspace)

        XCTAssertEqual(store.items(for: workspace).map(\.id), [open.id])
    }

    func testRemoveWorkspacePrunesPersistedItems() {
        let workspaceA = UUID()
        let workspaceB = UUID()
        let store = TodoStore(fileURL: tmpURL)

        _ = store.add(title: "A", workspaceId: workspaceA)
        _ = store.add(title: "B", workspaceId: workspaceB)
        store.removeWorkspace(workspaceA)

        let reload = TodoStore(fileURL: tmpURL)
        XCTAssertTrue(reload.items(for: workspaceA).isEmpty)
        XCTAssertEqual(reload.items(for: workspaceB).map(\.title), ["B"])
    }
}
