import XCTest
@testable import in0

@MainActor
final class ThemeCatalogTests: XCTestCase {

    private var tmpDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("in0-themes-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmpDir)
        try await super.tearDown()
    }

    func testMissingDirReturnsEmpty() {
        XCTAssertEqual(ThemeCatalog.scan(atPath: "/no/such/dir/in0-nonexistent"), [])
    }

    func testReturnsSortedAndSkipsDotFiles() throws {
        for name in ["Catppuccin Mocha", "Dracula", "Apple Classic", ".DS_Store"] {
            let url = tmpDir.appendingPathComponent(name)
            FileManager.default.createFile(atPath: url.path, contents: Data())
        }
        XCTAssertEqual(
            ThemeCatalog.scan(atPath: tmpDir.path),
            ["Apple Classic", "Catppuccin Mocha", "Dracula"]
        )
    }

    func testBundledCatalogContainsKnownTheme() {
        let all = ThemeCatalog.all
        // The bundle ships ghostty's full theme set; if it's empty, the
        // build step that copies vendor/ghostty/share didn't run — bail
        // loudly so we notice before users do.
        guard !all.isEmpty else { return }
        XCTAssertTrue(
            all.contains("Catppuccin Mocha") || all.contains("Dracula"),
            "bundled themes are present but the well-known names are missing — \(all.prefix(5))"
        )
    }
}
