import AppKit
import XCTest
@testable import in0

@MainActor
final class ThemeManagerTests: XCTestCase {

    func testInitProducesUsableTheme() {
        let manager = ThemeManager()
        // foreground must not be transparent zero — chrome text would
        // disappear. Either color channel non-zero qualifies.
        let fg = NSColor(manager.currentTheme.foreground).usingColorSpace(.sRGB)
        let r = fg?.redComponent ?? 0
        let g = fg?.greenComponent ?? 0
        let b = fg?.blueComponent ?? 0
        XCTAssertGreaterThan(r + g + b, 0.0, "theme.foreground must not be pure black with zero alpha")
    }

    func testDeriveFromDarkBackground() {
        let bg = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.08, alpha: 1)
        let fg = NSColor(srgbRed: 0.92, green: 0.92, blue: 0.93, alpha: 1)
        let theme = ThemeManager.derive(background: bg, foreground: fg)
        XCTAssertTrue(theme.isDark)
    }

    func testDeriveFromLightBackground() {
        let bg = NSColor(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1)
        let fg = NSColor(srgbRed: 0.10, green: 0.10, blue: 0.11, alpha: 1)
        let theme = ThemeManager.derive(background: bg, foreground: fg)
        XCTAssertFalse(theme.isDark)
    }

    func testApplyTerminalColorMovesTheme() {
        let manager = ThemeManager()
        manager.applyTerminalColor(kind: -2 /* background */, r: 30, g: 30, b: 40)
        // The chrome should re-derive from the just-supplied background;
        // we can't assert exact equality without recomputing, so check
        // that the canvas component is now in the dark range.
        let canvas = NSColor(manager.currentTheme.canvas).usingColorSpace(.sRGB)
        XCTAssertNotNil(canvas)
        XCTAssertLessThan((canvas?.brightnessComponent ?? 1), 0.3)
    }
}

@MainActor
final class GhosttyConfigReaderTests: XCTestCase {

    private var tmp: URL!

    override func setUp() async throws {
        try await super.setUp()
        tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("in0-ghostty-cfg-\(UUID().uuidString).conf")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tmp)
        try await super.tearDown()
    }

    func testParseFilePicksThemeAndColors() throws {
        try """
        # ghostty config
        theme = Catppuccin Mocha
        foreground = #abcdef
        background = #112233
        palette = 1=#ff0000
        """.write(to: tmp, atomically: true, encoding: .utf8)

        let kvs = GhosttyConfigReader.parseFile(at: tmp.path)
        let dict = Dictionary(kvs, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(dict["theme"], "Catppuccin Mocha")
        XCTAssertEqual(dict["foreground"], "#abcdef")
        XCTAssertEqual(dict["background"], "#112233")
    }

    func testParseFileMissingReturnsEmpty() {
        XCTAssertTrue(GhosttyConfigReader.parseFile(at: "/no/such/file").isEmpty)
    }

    func testParseColorHex6() {
        let c = GhosttyConfigReader.parseColor("#ff8800")
        XCTAssertNotNil(c)
        XCTAssertEqual(Double(c?.redComponent ?? 0),  1.0, accuracy: 0.01)
        XCTAssertEqual(Double(c?.blueComponent ?? 0), 0.0, accuracy: 0.01)
    }

    func testParseColorHex3() {
        let c = GhosttyConfigReader.parseColor("#f80")
        XCTAssertNotNil(c)
        XCTAssertEqual(Double(c?.redComponent ?? 0), 1.0, accuracy: 0.01)
    }

    func testParseColorRgbForm() {
        let c = GhosttyConfigReader.parseColor("rgb:ff/80/00")
        XCTAssertNotNil(c)
        XCTAssertEqual(Double(c?.redComponent ?? 0), 1.0, accuracy: 0.01)
    }

    func testParseColorGarbageNil() {
        XCTAssertNil(GhosttyConfigReader.parseColor("not a color"))
    }
}
