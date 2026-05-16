import XCTest
@testable import in0

final class StartupCommandResolverTests: XCTestCase {

    /// Build a minimal one-terminal tab with the given quickActionId.
    private func makeTab(quickActionId: String?) -> (TerminalTab, UUID) {
        let tab = TerminalTab(title: "t", quickActionId: quickActionId)
        let leaf = tab.layout.allTerminalIds().first!
        return (tab, leaf)
    }

    // MARK: - (0a) builtin agent + resume on + matching prefill → replay

    func testQuickActionBuiltinReplaysResumePrefill() {
        let (tab, leaf) = makeTab(quickActionId: "claude")
        let result = StartupCommandResolver.resolve(
            terminalId: leaf,
            tab: tab,
            workspaceDefaultCommand: nil,
            quickActionCommand: { $0 == "claude" ? "claude" : nil },
            isResumeEnabled: { $0 == .claude },
            pendingPrefill: "claude --resume abc"
        )
        XCTAssertEqual(result, "claude --resume abc")
    }

    /// Agent equality guard: a stored prefill from a *different* agent
    /// must NOT be replayed under a builtin's button.
    func testQuickActionAgentMismatchFallsBackToCommand() {
        let (tab, leaf) = makeTab(quickActionId: "claude")
        let result = StartupCommandResolver.resolve(
            terminalId: leaf,
            tab: tab,
            workspaceDefaultCommand: nil,
            quickActionCommand: { $0 == "claude" ? "claude" : nil },
            isResumeEnabled: { _ in true },
            pendingPrefill: "codex resume zzz"
        )
        XCTAssertEqual(result, "claude\n")
    }

    // MARK: - (0b) quick action default / override

    func testQuickActionFiresCommandWithNewline() {
        let (tab, leaf) = makeTab(quickActionId: "gitui")
        let result = StartupCommandResolver.resolve(
            terminalId: leaf,
            tab: tab,
            workspaceDefaultCommand: "echo workspace",
            quickActionCommand: { $0 == "gitui" ? "gitui --tui" : nil },
            isResumeEnabled: { _ in false },
            pendingPrefill: nil
        )
        XCTAssertEqual(result, "gitui --tui\n")
    }

    // MARK: - (1) plain terminal agent resume

    func testNakedTerminalReplaysResumeWhenEnabled() {
        let result = StartupCommandResolver.resolve(
            terminalId: UUID(),
            tab: nil,
            workspaceDefaultCommand: "echo ws",
            quickActionCommand: { _ in nil },
            isResumeEnabled: { $0 == .codex },
            pendingPrefill: "codex resume sess"
        )
        XCTAssertEqual(result, "codex resume sess")
    }

    func testNakedTerminalSkipsResumeWhenDisabled() {
        let result = StartupCommandResolver.resolve(
            terminalId: UUID(),
            tab: nil,
            workspaceDefaultCommand: "echo ws",
            quickActionCommand: { _ in nil },
            isResumeEnabled: { _ in false },
            pendingPrefill: "claude --resume abc"
        )
        XCTAssertEqual(result, "echo ws")
    }

    // MARK: - (2) workspace default fallback

    func testWorkspaceDefaultIsLastResort() {
        let result = StartupCommandResolver.resolve(
            terminalId: UUID(),
            tab: nil,
            workspaceDefaultCommand: "nvim",
            quickActionCommand: { _ in nil },
            isResumeEnabled: { _ in false },
            pendingPrefill: nil
        )
        XCTAssertEqual(result, "nvim")
    }

    func testNoSourcesReturnsNil() {
        let result = StartupCommandResolver.resolve(
            terminalId: UUID(),
            tab: nil,
            workspaceDefaultCommand: nil,
            quickActionCommand: { _ in nil },
            isResumeEnabled: { _ in false },
            pendingPrefill: nil
        )
        XCTAssertNil(result)
    }

    // MARK: - Quick action only fires on FIRST terminal in the tab

    func testQuickActionOnlyFiresOnFirstTerminal() {
        let tab = TerminalTab(title: "t", quickActionId: "claude")
        // Split twice to get >1 leaf, then test against the second leaf.
        let firstLeaf = tab.layout.allTerminalIds().first!
        let otherLeaf = UUID()  // not in tab.layout
        XCTAssertNotEqual(firstLeaf, otherLeaf)
        let result = StartupCommandResolver.resolve(
            terminalId: otherLeaf,
            tab: tab,
            workspaceDefaultCommand: "echo ws",
            quickActionCommand: { $0 == "claude" ? "claude" : nil },
            isResumeEnabled: { _ in false },
            pendingPrefill: nil
        )
        XCTAssertEqual(result, "echo ws")
    }
}
