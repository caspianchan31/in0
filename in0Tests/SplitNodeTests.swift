import XCTest
@testable import in0

/// Tree-walk correctness for SplitNode.neighbor — the core of ⌘⌥arrow focus.
final class SplitNodeTests: XCTestCase {

    /// A vertical split (panes side-by-side): left ↔ right neighbors.
    func testHorizontalNeighborInVerticalSplit() {
        let a = UUID(), b = UUID()
        let root = SplitNode.split(
            id: UUID(), direction: .vertical, firstRatio: 0.5,
            first: .terminal(a), second: .terminal(b)
        )
        XCTAssertEqual(root.neighbor(of: a, direction: .right), b)
        XCTAssertEqual(root.neighbor(of: b, direction: .left), a)
        XCTAssertNil(root.neighbor(of: a, direction: .left))
        XCTAssertNil(root.neighbor(of: a, direction: .up))
    }

    /// A horizontal split (panes stacked): up ↔ down neighbors.
    func testVerticalNeighborInHorizontalSplit() {
        let top = UUID(), bot = UUID()
        let root = SplitNode.split(
            id: UUID(), direction: .horizontal, firstRatio: 0.5,
            first: .terminal(top), second: .terminal(bot)
        )
        XCTAssertEqual(root.neighbor(of: top, direction: .down), bot)
        XCTAssertEqual(root.neighbor(of: bot, direction: .up), top)
        XCTAssertNil(root.neighbor(of: top, direction: .left))
    }

    /// Nested: outer vertical split, inner horizontal on the right.
    /// Moving "left" from inner-top should land on the outer-left leaf.
    func testNestedNeighborTraversal() {
        let l = UUID(), rt = UUID(), rb = UUID()
        let right = SplitNode.split(
            id: UUID(), direction: .horizontal, firstRatio: 0.5,
            first: .terminal(rt), second: .terminal(rb)
        )
        let root = SplitNode.split(
            id: UUID(), direction: .vertical, firstRatio: 0.5,
            first: .terminal(l), second: right
        )
        XCTAssertEqual(root.neighbor(of: rt, direction: .left), l)
        XCTAssertEqual(root.neighbor(of: rb, direction: .left), l)
        XCTAssertEqual(root.neighbor(of: rt, direction: .down), rb)
        XCTAssertEqual(root.neighbor(of: rb, direction: .up), rt)
    }

    /// dropTabIntoPane direction mapping: NSRectEdge → SplitDirection.
    /// (Indirect: exercise WorkspaceStore.dropTabIntoPane and inspect layout.)
    @MainActor
    func testDropTabIntoPaneFormsExpectedDirection() {
        UserDefaults.standard.removeObject(forKey: "in0.workspaces.v1")
        let store = WorkspaceStore()
        guard let ws = store.workspaces.first else { return XCTFail() }
        let srcTab = store.addTab(to: ws.id, title: "src")!
        let dstTab = store.addTab(to: ws.id, title: "dst")!
        let dstLeaf = dstTab.layout.allTerminalIds().first!

        store.dropTabIntoPane(
            in: ws.id,
            droppedTabId: srcTab.id,
            targetTabId: dstTab.id,
            targetTerminalId: dstLeaf,
            edge: .maxX // right edge → vertical split, dropped becomes "second"
        )

        let updatedWs = store.workspaces.first { $0.id == ws.id }!
        XCTAssertNil(updatedWs.tabs.first { $0.id == srcTab.id }, "source tab should be removed")
        let updatedDst = updatedWs.tabs.first { $0.id == dstTab.id }!
        if case .split(_, let dir, _, _, _) = updatedDst.layout {
            XCTAssertEqual(dir, .vertical)
        } else {
            XCTFail("expected a split after drop")
        }
    }
}
