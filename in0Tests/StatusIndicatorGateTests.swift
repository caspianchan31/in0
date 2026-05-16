import XCTest
@testable import in0

@MainActor
final class StatusIndicatorGateTests: XCTestCase {

    private var tmpPath: String!
    private var settings: SettingsConfigStore!

    override func setUp() async throws {
        try await super.setUp()
        tmpPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("in0-gate-\(UUID().uuidString).conf")
        settings = SettingsConfigStore(filePath: tmpPath)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: tmpPath)
        try await super.tearDown()
    }

    func testGateTrueWithDefaults() {
        // Defaults: claude=false, codex=true, opencode=true → at least
        // one agent on, gate fires.
        XCTAssertTrue(StatusIndicatorGate.anyAgentEnabled(settings))
    }

    func testGateFalseWhenAllAgentsExplicitlyOff() {
        for agent in HookAgent.allCases {
            settings.set("agent-\(agent.rawValue)-notifications", "false")
        }
        settings.save()
        XCTAssertFalse(StatusIndicatorGate.anyAgentEnabled(settings))
    }

    func testGateTrueWhenOnlyClaudeOn() {
        for agent in HookAgent.allCases {
            settings.set("agent-\(agent.rawValue)-notifications", "false")
        }
        settings.set("agent-claude-notifications", "true")
        settings.save()
        XCTAssertTrue(StatusIndicatorGate.anyAgentEnabled(settings))
    }

    func testGateTrueWhenOnlyCodexOn() {
        for agent in HookAgent.allCases {
            settings.set("agent-\(agent.rawValue)-notifications", "false")
        }
        settings.set("agent-codex-notifications", "true")
        settings.save()
        XCTAssertTrue(StatusIndicatorGate.anyAgentEnabled(settings))
    }

    func testGateTrueWhenOnlyOpenCodeOn() {
        for agent in HookAgent.allCases {
            settings.set("agent-\(agent.rawValue)-notifications", "false")
        }
        settings.set("agent-opencode-notifications", "true")
        settings.save()
        XCTAssertTrue(StatusIndicatorGate.anyAgentEnabled(settings))
    }

    func testLegacyMasterKeyIsIgnored() {
        // A pre-2026-04 user config might still carry a stray
        // `status-indicators-enabled = true` line. The gate should not
        // resurrect the feature on that key alone — only the per-agent
        // toggles count for "is anything to display".
        for agent in HookAgent.allCases {
            settings.set("agent-\(agent.rawValue)-notifications", "false")
        }
        settings.set("status-indicators-enabled", "true")
        settings.save()
        XCTAssertFalse(StatusIndicatorGate.anyAgentEnabled(settings))
    }
}
