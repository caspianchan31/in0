import XCTest
@testable import in0

/// Verifies the per-agent gating in HookDispatcher: notifications can be
/// suppressed per agent (Claude's 60s heartbeat), and resume commands are
/// only persisted when the per-agent toggle says to.
@MainActor
final class HookDispatcherTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "in0.resumeCommands.v1")
    }

    /// Build a SettingsStore backed by an ephemeral config file under
    /// /tmp so each test gets a clean slate without colliding with the
    /// real `~/Library/Application Support/in0/config`.
    @MainActor
    private func makeSettings() -> SettingsStore {
        let path = "/tmp/in0-test-\(UUID().uuidString).config"
        let cfg = SettingsConfigStore(filePath: path)
        return SettingsStore(configStore: cfg)
    }

    func testNeedsInputSuppressedWhenAgentNotificationsOff() {
        let statuses = TerminalStatusStore()
        let settings = makeSettings()
        settings.setNotifications(false, for: .claude)
        let dispatcher = HookDispatcher(store: statuses, settings: settings)

        let tid = UUID()
        dispatcher.handle(HookMessage(terminalId: tid, event: .running, agent: .claude))
        dispatcher.handle(HookMessage(terminalId: tid, event: .needsInput, agent: .claude))

        // Status should remain running, not flip to needsInput.
        if case .running = statuses.status(for: tid) {} else {
            XCTFail("status should still be running with notifications off")
        }
    }

    func testNeedsInputAppliedWhenAgentNotificationsOn() {
        let statuses = TerminalStatusStore()
        let settings = makeSettings()
        settings.setNotifications(true, for: .codex)
        let dispatcher = HookDispatcher(store: statuses, settings: settings)

        let tid = UUID()
        dispatcher.handle(HookMessage(terminalId: tid, event: .running, agent: .codex))
        dispatcher.handle(HookMessage(terminalId: tid, event: .needsInput, agent: .codex))

        if case .needsInput = statuses.status(for: tid) {} else {
            XCTFail("needsInput should propagate when notifications are on")
        }
    }

    func testResumeOnlyRecordedWhenToggleOn() {
        let statuses = TerminalStatusStore()
        let settings = makeSettings()
        settings.setResumeOnLaunch(false, for: .claude)
        let dispatcher = HookDispatcher(store: statuses, settings: settings)

        let tid = UUID()
        var msg = HookMessage(terminalId: tid, event: .finished, agent: .claude)
        msg.resumeCommand = "claude --resume abc"
        dispatcher.handle(msg)
        XCTAssertNil(ResumeStore.shared.consume(terminalId: tid))

        settings.setResumeOnLaunch(true, for: .claude)
        dispatcher.handle(msg)
        XCTAssertEqual(ResumeStore.shared.consume(terminalId: tid), "claude --resume abc")
    }

    func testRepeatedRunningKeepsOriginalStartForDuration() {
        let statuses = TerminalStatusStore()
        let settings = makeSettings()
        let dispatcher = HookDispatcher(store: statuses, settings: settings)

        let tid = UUID()
        dispatcher.handle(HookMessage(terminalId: tid, event: .running, agent: .codex, at: 10))
        dispatcher.handle(HookMessage(terminalId: tid, event: .running, agent: .codex, at: 20))
        dispatcher.handle(HookMessage(terminalId: tid, event: .finished, agent: .codex, at: 25))

        if case .success(_, let duration, _, _, _, _) = statuses.status(for: tid) {
            XCTAssertEqual(duration, 15, accuracy: 0.001)
        } else {
            XCTFail("expected success")
        }
    }
}
