import XCTest
@testable import in0

@MainActor
final class UpdateStoreTests: XCTestCase {

    func testDefaultStateIsIdle() {
        XCTAssertEqual(UpdateStore(currentVersion: "0.1.0").state, .idle)
    }

    func testCurrentVersionStoredVerbatim() {
        XCTAssertEqual(UpdateStore(currentVersion: "1.2.3").currentVersion, "1.2.3")
    }

    func testHasUpdateFalseWhenIdle() {
        XCTAssertFalse(UpdateStore(currentVersion: "0.1.0").hasUpdate)
    }

    func testUpdateAvailableLifecycle() {
        let store = UpdateStore(currentVersion: "0.1.0")
        store.setUpdateAvailable(version: "0.2.0", notes: "fix bug")
        XCTAssertTrue(store.hasUpdate)
        XCTAssertEqual(store.state, .updateAvailable(version: "0.2.0", releaseNotes: "fix bug"))
    }

    func testDownloadingKeepsHasUpdateTrue() {
        let store = UpdateStore(currentVersion: "0.1.0")
        store.setUpdateAvailable(version: "0.2.0", notes: nil)
        store.setDownloading(progress: 0.3)
        XCTAssertTrue(store.hasUpdate)
        XCTAssertEqual(store.state, .downloading(progress: 0.3))
    }

    func testUpToDateClearsHasUpdate() {
        let store = UpdateStore(currentVersion: "0.1.0")
        store.setChecking()
        store.setUpToDate()
        XCTAssertFalse(store.hasUpdate)
        XCTAssertEqual(store.state, .upToDate)
    }

    func testErrorStateKeepsHasUpdateFalse() {
        let store = UpdateStore(currentVersion: "0.1.0")
        store.setError("Network error")
        XCTAssertEqual(store.state, .error("Network error"))
        XCTAssertFalse(store.hasUpdate)
    }

    func testResetToIdle() {
        let store = UpdateStore(currentVersion: "0.1.0")
        store.setUpdateAvailable(version: "0.2.0", notes: nil)
        store.resetToIdle()
        XCTAssertEqual(store.state, .idle)
    }

    func testProgressUpdatesAcceptMonotonic() {
        let store = UpdateStore(currentVersion: "0.1.0")
        store.setDownloading(progress: 0.1)
        store.setDownloading(progress: 0.5)
        store.setDownloading(progress: 1.0)
        XCTAssertEqual(store.state, .downloading(progress: 1.0))
    }

    func testReadyToInstallKeepsHasUpdateTrue() {
        let store = UpdateStore(currentVersion: "0.1.0")
        store.setReadyToInstall()
        XCTAssertTrue(store.hasUpdate)
        XCTAssertEqual(store.state, .readyToInstall)
    }

    func testSparkleBridgeStubbedWhenUnlinked() {
        // The Sparkle SPM dep is commented out by default (offline-safe).
        // isActive must report false so tests never touch the network.
        XCTAssertFalse(SparkleBridge.shared.isActive)
    }
}
