import XCTest
@testable import in0

@MainActor
final class SettingsConfigStoreTests: XCTestCase {

    private var tmpPath: String!

    override func setUp() async throws {
        try await super.setUp()
        tmpPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("in0-settings-\(UUID().uuidString).conf")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tmpPath)
        try await super.tearDown()
    }

    func testMissingFileLoadsAsEmpty() {
        let store = SettingsConfigStore(filePath: tmpPath)
        store.reload()
        XCTAssertNil(store.get("font-size"))
    }

    func testParserKeepsCommentsBlanksUnknownsRoundtrippable() throws {
        let contents = """
        # top comment

        font-size = 13
        theme = Catppuccin Mocha
        # trailing comment
        garbage-no-equals
        """
        try contents.write(toFile: tmpPath, atomically: true, encoding: .utf8)

        let store = SettingsConfigStore(filePath: tmpPath)
        store.reload()
        XCTAssertEqual(store.get("font-size"), "13")
        XCTAssertEqual(store.get("theme"), "Catppuccin Mocha")

        let counts = store.debugCounts()
        XCTAssertEqual(counts.comments, 2)
        XCTAssertEqual(counts.blanks, 1)
        XCTAssertEqual(counts.unknowns, 1)
        XCTAssertEqual(counts.kvs, 2)
    }

    func testSetExistingKeyUpdatesInPlace() throws {
        try "font-size = 13\ntheme = A\n".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        let store = SettingsConfigStore(filePath: tmpPath)
        store.reload()
        store.set("font-size", "15")
        store.save()

        let roundTrip = try String(contentsOfFile: tmpPath, encoding: .utf8)
        XCTAssertTrue(roundTrip.contains("font-size = 15"))
        XCTAssertTrue(roundTrip.contains("theme = A"))
        XCTAssertFalse(roundTrip.contains("font-size = 13"))
    }

    func testSetNewKeyAppendsAfterExistingContent() throws {
        try "# user comment\n\ntheme = A\n".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        let store = SettingsConfigStore(filePath: tmpPath)
        store.reload()
        store.set("font-size", "15")
        store.save()

        let roundTrip = try String(contentsOfFile: tmpPath, encoding: .utf8)
        XCTAssertTrue(roundTrip.hasPrefix("# user comment"))
        let themeIdx = roundTrip.range(of: "theme = A")!.lowerBound
        let fontIdx  = roundTrip.range(of: "font-size = 15")!.lowerBound
        XCTAssertLessThan(themeIdx, fontIdx, "appended key must land after existing kvs")
    }

    func testSetNilRemovesLine() throws {
        try "font-size = 13\ntheme = A\n".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        let store = SettingsConfigStore(filePath: tmpPath)
        store.reload()
        store.set("font-size", nil)
        store.save()

        let roundTrip = try String(contentsOfFile: tmpPath, encoding: .utf8)
        XCTAssertFalse(roundTrip.contains("font-size"))
        XCTAssertTrue(roundTrip.contains("theme = A"))
    }

    func testPreservesDuplicateKeysOnRoundTrip() throws {
        let contents = """
        palette = 0=#000000
        palette = 1=#ffffff
        """
        try contents.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        let store = SettingsConfigStore(filePath: tmpPath)
        store.reload()

        // `get` returns the first occurrence — both lines must survive.
        XCTAssertEqual(store.get("palette"), "0=#000000")
        store.save()

        let roundTrip = try String(contentsOfFile: tmpPath, encoding: .utf8)
        XCTAssertTrue(roundTrip.contains("palette = 0=#000000"))
        XCTAssertTrue(roundTrip.contains("palette = 1=#ffffff"))
    }

    func testQuotedValueIsUnwrapped() throws {
        try #"theme = "Catppuccin Latte""#.write(toFile: tmpPath, atomically: true, encoding: .utf8)
        let store = SettingsConfigStore(filePath: tmpPath)
        store.reload()
        XCTAssertEqual(store.get("theme"), "Catppuccin Latte")
    }

    func testSetSameValueShortCircuits() {
        // Critical for SwiftUI TextField focus: a Binding's setter fires
        // with the current value on focus change. If `set` always wrote +
        // dispatched `onChange`, every focus tick would reload the theme
        // and steal focus back.
        let store = SettingsConfigStore(filePath: tmpPath)
        var changed = 0
        store.onChange = { changed += 1 }
        store.set("theme", "A")           // first write — should trigger
        store.set("theme", "A")           // same value — should NOT trigger
        // Drain the 200 ms debounced async write so onChange has a chance to fire.
        let expect = expectation(description: "wait debounce")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { expect.fulfill() }
        wait(for: [expect], timeout: 1.0)
        XCTAssertEqual(changed, 1, "onChange must fire exactly once for a stable value")
    }
}
