import XCTest
@testable import in0

final class AIHistoryStoreTests: XCTestCase {
    private var tempDirs: [URL] = []

    override func tearDown() {
        for url in tempDirs {
            try? FileManager.default.removeItem(at: url)
        }
        tempDirs.removeAll()
        super.tearDown()
    }

    func testScanFindsWorkspaceAIHistoryFiles() throws {
        let root = try makeTempDir()
        let codexDir = root.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let file = codexDir.appendingPathComponent("codex-session-123.jsonl")
        try #"{"role":"assistant","content":"Implemented the sidebar fix."}"#
            .write(to: file, atomically: true, encoding: .utf8)

        let result = try performLocalScan(root: root)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.agent, "Codex")
        XCTAssertEqual(result.entries.first?.relativePath, ".codex/sessions/codex-session-123.jsonl")
        XCTAssertTrue(result.entries.first?.snippet.contains("Implemented the sidebar fix") == true)
        XCTAssertEqual(result.entries.first?.resumeCommand, "codex resume codex-session-123")
    }

    func testScanBuildsResumeCommandFromSessionId() throws {
        let root = try makeTempDir()
        let claudeDir = root.appendingPathComponent(".claude/projects", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let file = claudeDir.appendingPathComponent("conversation.jsonl")
        try #"{"sessionId":"claude-session-456","message":"continue work"}"#
            .write(to: file, atomically: true, encoding: .utf8)

        let result = try performLocalScan(root: root)

        XCTAssertEqual(result.entries.first?.agent, "Claude")
        XCTAssertEqual(result.entries.first?.resumeCommand, "claude --resume claude-session-456")
    }

    func testScanFindsGlobalClaudeProjectSessionsForWorkspace() throws {
        let root = try makeTempDir()
        let home = try makeTempDir()
        let claudeDir = home.appendingPathComponent(".claude/projects/-tmp-workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let file = claudeDir.appendingPathComponent("92596567-4cf9-4a63-bb27-e32fbdf0bdc2.jsonl")
        try """
        {"type":"permission-mode","sessionId":"92596567-4cf9-4a63-bb27-e32fbdf0bdc2"}
        {"type":"user","message":{"role":"user","content":"continue app work"},"cwd":"\(root.path)"}
        """
            .write(to: file, atomically: true, encoding: .utf8)

        let result = AIHistoryStore.performScan(rootPath: root.path, homePath: home.path)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.entries.first?.agent, "Claude")
        XCTAssertEqual(result.entries.first?.resumeCommand, "claude --resume 92596567-4cf9-4a63-bb27-e32fbdf0bdc2")
    }

    func testScanFindsGlobalCodexSessionsForWorkspace() throws {
        let root = try makeTempDir()
        let home = try makeTempDir()
        let codexDir = home.appendingPathComponent(".codex/sessions/2026/05/16", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let file = codexDir.appendingPathComponent("rollout-2026-05-16T20-39-49-019e30cc-d1e7-78d1-87c9-682a931e2953.jsonl")
        try """
        {"type":"session_meta","payload":{"id":"019e30cc-d1e7-78d1-87c9-682a931e2953","cwd":"\(root.path)"}}
        {"type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"继续优化性能"}]}}
        """
            .write(to: file, atomically: true, encoding: .utf8)

        let result = AIHistoryStore.performScan(rootPath: root.path, homePath: home.path)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.entries.first?.agent, "Codex")
        XCTAssertEqual(result.entries.first?.resumeCommand, "codex resume 019e30cc-d1e7-78d1-87c9-682a931e2953")
    }

    func testScanDoesNotTreatClaudeSettingsAsResumeSession() throws {
        let root = try makeTempDir()
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let settings = claudeDir.appendingPathComponent("settings.json")
        try #"{"permissions":{"allow":["Bash(git status)"]}}"#
            .write(to: settings, atomically: true, encoding: .utf8)
        let localSettings = claudeDir.appendingPathComponent("settings.local.json")
        try #"{"permissions":{"allow":["Read(//Users/example/**)"]}}"#
            .write(to: localSettings, atomically: true, encoding: .utf8)

        let result = try performLocalScan(root: root)

        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.error, "No AI history files found in this workspace.")
    }

    func testFilenameResumeFallbackRequiresSessionDirectory() throws {
        let root = try makeTempDir()
        let claudeDir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        let notSession = claudeDir.appendingPathComponent("abcdefgh.jsonl")
        try #"{"message":"looks like history but is not in a session directory"}"#
            .write(to: notSession, atomically: true, encoding: .utf8)

        let result = try performLocalScan(root: root)

        XCTAssertEqual(result.entries.first?.relativePath, ".claude/abcdefgh.jsonl")
        XCTAssertNil(result.entries.first?.resumeCommand)
    }

    func testScanFindsRootConversationNamedFiles() throws {
        let root = try makeTempDir()
        let file = root.appendingPathComponent("team-conversation.md")
        try "User: add plugin\nAssistant: done".write(to: file, atomically: true, encoding: .utf8)

        let result = try performLocalScan(root: root)

        XCTAssertEqual(result.entries.map(\.relativePath), ["team-conversation.md"])
        XCTAssertEqual(result.entries.first?.agent, "AI")
    }

    func testScanReturnsAllMatchedHistoryEntries() throws {
        let root = try makeTempDir()
        let codexDir = root.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        for index in 0..<25 {
            let file = codexDir.appendingPathComponent("session-\(index).jsonl")
            try #"{"role":"user","content":"history entry \#(index)"}"#
                .write(to: file, atomically: true, encoding: .utf8)
        }

        let result = try performLocalScan(root: root)

        XCTAssertEqual(result.entries.count, 25)
    }

    func testScanIgnoresLargeFiles() throws {
        let root = try makeTempDir()
        let dir = root.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("history.log")
        let oversized = String(repeating: "x", count: 600 * 1024)
        try oversized.write(to: file, atomically: true, encoding: .utf8)

        let result = try performLocalScan(root: root)

        XCTAssertTrue(result.entries.isEmpty)
        XCTAssertEqual(result.error, "No AI history files found in this workspace.")
    }

    func testMissingWorkspaceReturnsError() {
        let result = AIHistoryStore.performScan(rootPath: "/tmp/in0-missing-\(UUID().uuidString)")

        XCTAssertEqual(result.error, "Workspace folder no longer exists.")
    }

    @MainActor
    func testResumeImportScansHistoryLaunchesTabAndQueuesCommand() throws {
        let root = try makeTempDir()
        let codexDir = root.appendingPathComponent(".codex/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let file = codexDir.appendingPathComponent("session-abcdef12.jsonl")
        try #"{"role":"assistant","content":"Ready to continue."}"#
            .write(to: file, atomically: true, encoding: .utf8)

        let result = try performLocalScan(root: root)
        let command = try XCTUnwrap(result.entries.first?.resumeCommand)

        let key = "in0.test.ai-history.resume.\(UUID())"
        let store = WorkspaceStore(persistenceKey: key, seedDefault: false)
        let workspace = store.addWorkspace(name: "repo", rootPath: root.path)
        let tab = try XCTUnwrap(store.launchCommandInNewTab(
            workspaceId: workspace.id,
            title: "Codex resume",
            command: command
        ))
        let terminalId = try XCTUnwrap(tab.layout.allTerminalIds().first)

        XCTAssertEqual(store.selectedId, workspace.id)
        XCTAssertEqual(store.selectedWorkspace?.selectedTabId, tab.id)
        XCTAssertEqual(TerminalCommandQueue.shared.drain(for: terminalId), "codex resume session-abcdef12")
        XCTAssertNil(TerminalCommandQueue.shared.drain(for: terminalId))

        UserDefaults.standard.removeObject(forKey: key)
    }

    private func makeTempDir() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("in0-ai-history-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func performLocalScan(root: URL) throws -> AIHistoryResult {
        let isolatedHome = try makeTempDir()
        return AIHistoryStore.performScan(rootPath: root.path, homePath: isolatedHome.path)
    }
}
