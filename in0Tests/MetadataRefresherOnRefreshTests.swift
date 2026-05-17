import XCTest
@testable import in0

private final class LookupCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.lock()
        value += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

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

    func testTickCoalescesDuplicatePwdLookups() {
        let key = "in0.test.metadata.\(UUID().uuidString)"
        let pwdKey = "in0.test.pwds.\(UUID().uuidString)"
        let workspaces = WorkspaceStore(persistenceKey: key, seedDefault: false)
        let pwds = TerminalPwdStore(persistenceKey: pwdKey)
        workspaces.seedPwdPolicy = { terminalId, pwd in
            pwds.setPwd(pwd, for: terminalId)
        }
        _ = workspaces.addWorkspace(name: "one", rootPath: "/tmp/in0-shared")
        _ = workspaces.addWorkspace(name: "two", rootPath: "/tmp/in0-shared")

        let branchLookups = LookupCounter()
        let prLookups = LookupCounter()
        let metadata = WorkspaceMetadataStore()
        let refresher = MetadataRefresher(
            workspaces: workspaces,
            pwds: pwds,
            metadata: metadata,
            branchResolver: { path in
                branchLookups.increment()
                return path.hasSuffix("in0-shared") ? "main" : nil
            },
            prCountResolver: { _ in
                prLookups.increment()
                return 2
            }
        )

        let exp = expectation(description: "onRefresh fires once")
        refresher.onRefresh = { exp.fulfill() }
        refresher.start(interval: 10)
        wait(for: [exp], timeout: 5)
        refresher.stop()

        XCTAssertEqual(branchLookups.count, 1)
        XCTAssertEqual(prLookups.count, 1)
        XCTAssertEqual(metadata.snapshots.count, 2)

        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: pwdKey)
    }
}
