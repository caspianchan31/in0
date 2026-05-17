import XCTest
@testable import in0

@MainActor
final class MetadataRefresherTests: XCTestCase {

    func testParseBranchFromGitOutput() {
        XCTAssertEqual(MetadataRefresher.parseBranch(from: "main\n"), "main")
    }

    func testParseBranchTrimsBothEnds() {
        XCTAssertEqual(MetadataRefresher.parseBranch(from: "  feat/sidebar  \n"), "feat/sidebar")
    }

    func testParseEmptyReturnsNil() {
        XCTAssertNil(MetadataRefresher.parseBranch(from: ""))
        XCTAssertNil(MetadataRefresher.parseBranch(from: "   \n"))
    }

    func testPrStatusFormatsPositiveCountsOnly() {
        XCTAssertNil(MetadataRefresher.prStatus(for: nil))
        XCTAssertNil(MetadataRefresher.prStatus(for: 0))
        XCTAssertEqual(MetadataRefresher.prStatus(for: 1), "1 PR")
        XCTAssertEqual(MetadataRefresher.prStatus(for: 3), "3 PRs")
    }

    func testMetadataStoreSkipsTimestampOnlyUpdates() {
        let store = WorkspaceMetadataStore()
        let id = UUID()
        let first = WorkspaceMetadataSnapshot(
            gitBranch: "main",
            pwd: "/tmp/repo",
            openPRCount: 1,
            unreadNotifications: nil,
            prStatus: "1 PR",
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let second = WorkspaceMetadataSnapshot(
            gitBranch: "main",
            pwd: "/tmp/repo",
            openPRCount: 1,
            unreadNotifications: nil,
            prStatus: "1 PR",
            updatedAt: Date(timeIntervalSince1970: 20)
        )

        store.set(first, for: id)
        store.set(second, for: id)

        XCTAssertEqual(store.snapshot(for: id)?.updatedAt, first.updatedAt)
    }
}
