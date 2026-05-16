import XCTest
@testable import in0

/// Behavior tests for WorkspaceStore mutation paths exercised by the
/// keyboard / drag / Quick Action surface. Tests reset UserDefaults keys
/// the store touches to keep runs independent.
@MainActor
final class WorkspaceStoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        for key in ["in0.workspaces.v1", "in0.workspaces.v1.selected"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func testAddTabAndCloseTabReformsWorkspace() {
        let store = WorkspaceStore()
        let wsId = store.workspaces[0].id
        let t1 = store.workspaces[0].tabs[0].id

        let t2 = store.addTab(to: wsId, title: "two")!
        XCTAssertEqual(store.workspaces[0].tabs.count, 2)
        XCTAssertEqual(store.workspaces[0].selectedTabId, t2.id)

        store.closeTab(t2.id, in: wsId)
        XCTAssertEqual(store.workspaces[0].tabs.count, 1)
        XCTAssertEqual(store.workspaces[0].selectedTabId, t1)
    }

    func testMoveWorkspaceReorder() {
        let store = WorkspaceStore()
        let a = store.workspaces[0].id
        store.addWorkspace(name: "b")
        store.addWorkspace(name: "c")
        XCTAssertEqual(store.workspaces.map { $0.name }, ["default", "b", "c"])

        store.moveWorkspace(from: 0, to: 3)
        XCTAssertEqual(store.workspaces.map { $0.name }, ["b", "c", "default"])
        XCTAssertEqual(store.workspaces.last?.id, a)
    }

    func testRenameWorkspaceTrimsAndRejectsEmpty() {
        let store = WorkspaceStore()
        let wsId = store.workspaces[0].id

        store.renameWorkspace(wsId, to: "  Project  ")
        XCTAssertEqual(store.workspaces[0].name, "Project")

        store.renameWorkspace(wsId, to: "   ")
        XCTAssertEqual(store.workspaces[0].name, "Project")
    }

    func testSelectTabRejectsForeignId() {
        let store = WorkspaceStore()
        let wsId = store.workspaces[0].id
        let original = store.workspaces[0].selectedTabId

        store.selectTab(UUID(), in: wsId)
        XCTAssertEqual(store.workspaces[0].selectedTabId, original)
    }

    func testRemoveWorkspaceCleansTerminalState() {
        let store = WorkspaceStore()
        let ws = store.workspaces[0]
        let terminalId = ws.tabs[0].focusedTerminalId
        var cleaned: [UUID] = []
        store.terminalCleanup = { cleaned.append($0) }

        store.removeWorkspace(ws.id)

        XCTAssertTrue(store.workspaces.isEmpty)
        XCTAssertNil(store.selectedId)
        XCTAssertEqual(cleaned, [terminalId])
    }

    func testMoveTabReorder() {
        let store = WorkspaceStore()
        let wsId = store.workspaces[0].id
        let t1 = store.workspaces[0].tabs[0]
        let t2 = store.addTab(to: wsId, title: "b")!
        let t3 = store.addTab(to: wsId, title: "c")!
        XCTAssertEqual(store.workspaces[0].tabs.map { $0.title }, ["shell", "b", "c"])

        store.moveTab(in: wsId, from: 0, to: 3)
        XCTAssertEqual(store.workspaces[0].tabs.map { $0.id }, [t2.id, t3.id, t1.id])
    }

    func testSplitFocusedReplacesLeaf() {
        let store = WorkspaceStore()
        let wsId = store.workspaces[0].id
        let beforeIds = store.workspaces[0].tabs[0].layout.allTerminalIds()
        XCTAssertEqual(beforeIds.count, 1)

        let newId = store.splitFocused(in: wsId, direction: .vertical)!
        let afterIds = store.workspaces[0].tabs[0].layout.allTerminalIds()
        XCTAssertEqual(afterIds.count, 2)
        XCTAssertTrue(afterIds.contains(newId))
    }

    func testMoveFocusMovesAcrossSplits() {
        let store = WorkspaceStore()
        let wsId = store.workspaces[0].id
        let original = store.workspaces[0].tabs[0].focusedTerminalId
        let new = store.splitFocused(in: wsId, direction: .vertical)!
        XCTAssertEqual(store.workspaces[0].tabs[0].focusedTerminalId, new)

        store.moveFocus(.left)
        XCTAssertEqual(store.workspaces[0].tabs[0].focusedTerminalId, original)
        store.moveFocus(.right)
        XCTAssertEqual(store.workspaces[0].tabs[0].focusedTerminalId, new)
    }

    func testLaunchInNewTabUsesPolicyToEnqueueCommand() {
        let store = WorkspaceStore()
        // The new launchInNewTab marks the tab with its quickActionId and
        // defers command resolution to startupCommandPolicy. We simulate
        // what AppDelegate installs at runtime: a policy that maps the
        // quickActionId back to a shell command.
        store.startupCommandPolicy = { _, tab, _ in
            guard let id = tab.quickActionId else { return nil }
            return "\(id) --resume xyz"
        }
        store.launchInNewTab(title: "claude", quickActionId: "claude")
        let last = store.workspaces[0].tabs.last!
        XCTAssertEqual(last.quickActionId, "claude")
        let termId = last.layout.allTerminalIds().first!

        XCTAssertEqual(TerminalCommandQueue.shared.drain(for: termId), "claude --resume xyz")
        XCTAssertNil(TerminalCommandQueue.shared.drain(for: termId), "drain should be one-shot")
    }
}
