import XCTest
@testable import in0

@MainActor
final class MetadataRefresherOnRefreshTests: XCTestCase {

    /// Confirms the `onRefresh` hook fires on the main actor after the
    /// asynchronous tick lands a metadata write. Tests that depend on
    /// metadata side-effects (sidebar PR badge, branch label) use this
    /// to wait without sleeping.
    func testOnRefreshFiresOnMainAfterTick() {
        // Use a unique persistence key so we don't trample real state.
        let key = "in0.test.metadata.\(UUID().uuidString)"
        let workspaces = WorkspaceStore(persistenceKey: key, seedDefault: true)
        let pwds = TerminalPwdStore(persistenceKey: "test-\(UUID())")
        let metadata = WorkspaceMetadataStore()
        let refresher = MetadataRefresher(workspaces: workspaces, pwds: pwds, metadata: metadata)

        let exp = expectation(description: "onRefresh fires on main")
        refresher.onRefresh = {
            XCTAssertTrue(Thread.isMainThread)
            exp.fulfill()
        }

        // 1 s interval with a 0.1 s deadline kick — the source fires once
        // a second after start, but the `start()` method hands it a
        // `.now() + .seconds(1)` deadline; bump that down for the test.
        refresher.start(interval: 0.1)
        wait(for: [exp], timeout: 5)
        refresher.stop()

        UserDefaults.standard.removeObject(forKey: key)
    }
}
