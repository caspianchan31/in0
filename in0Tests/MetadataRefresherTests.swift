import XCTest
@testable import in0

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
}
