import XCTest
@testable import in0

final class PlaceholderTests: XCTestCase {
    func testWorkspaceStoreSeedsDefaultWorkspace() {
        // Wipe any persisted state from prior runs.
        let suite = "in0.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removeObject(forKey: "in0.workspaces.v1")

        // Just sanity: SplitNode round-trips.
        let leaf = UUID()
        let node = SplitNode.split(
            id: UUID(),
            direction: .horizontal,
            firstRatio: 0.5,
            first: .terminal(leaf),
            second: .terminal(UUID())
        )
        XCTAssertEqual(node.allTerminalIds().count, 2)
        XCTAssertTrue(node.allTerminalIds().contains(leaf))
    }
}
