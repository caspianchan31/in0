import XCTest
@testable import in0

final class QuickActionTests: XCTestCase {

    func testBuiltinAllCasesAreFour() {
        XCTAssertEqual(BuiltinQuickAction.allCases.count, 4)
        XCTAssertEqual(
            Set(BuiltinQuickAction.allCases.map(\.id)),
            Set(["gitui", "claude", "codex", "opencode"])
        )
    }

    func testBuiltinDefaultCommandsMatchId() {
        XCTAssertEqual(BuiltinQuickAction.gitui.defaultCommand,    "gitui")
        XCTAssertEqual(BuiltinQuickAction.claude.defaultCommand,   "claude")
        XCTAssertEqual(BuiltinQuickAction.codex.defaultCommand,    "codex")
        XCTAssertEqual(BuiltinQuickAction.opencode.defaultCommand, "opencode")
    }

    func testCustomActionCodableRoundTrip() throws {
        let original = CustomQuickAction(id: "abc-123", name: "htop", command: "htop -H")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CustomQuickAction.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testGituiIconIsSFSymbol() {
        guard case .sfSymbol(let name) = BuiltinQuickAction.gitui.iconSource else {
            XCTFail("expected sfSymbol"); return
        }
        XCTAssertEqual(name, "arrow.branch")
    }

    func testAgentIconsAreAssets() {
        for (action, expected) in [
            (BuiltinQuickAction.claude,   "quick-action-claudecode"),
            (BuiltinQuickAction.codex,    "quick-action-codex"),
            (BuiltinQuickAction.opencode, "quick-action-opencode"),
        ] {
            guard case .asset(let name) = action.iconSource else {
                XCTFail("\(action) expected .asset"); continue
            }
            XCTAssertEqual(name, expected)
        }
    }
}
