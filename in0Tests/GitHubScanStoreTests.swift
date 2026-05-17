import XCTest
@testable import in0

@MainActor
final class GitHubScanStoreTests: XCTestCase {
    private var tmpDirs: [URL] = []

    override func tearDown() async throws {
        for dir in tmpDirs { try? FileManager.default.removeItem(at: dir) }
        tmpDirs.removeAll()
        try await super.tearDown()
    }

    func testNilRootPathProducesUserFacingError() {
        let store = GitHubScanStore()
        let workspace = Workspace(name: "No Folder", rootPath: nil, tabs: [TerminalTab(title: "shell")])

        store.scan(workspace: workspace)

        let result = store.result(for: workspace.id)
        XCTAssertEqual(result?.rootPath, "No workspace folder")
        XCTAssertEqual(result?.error, "Choose a folder for this workspace first.")
        XCTAssertFalse(store.runningWorkspaceIds.contains(workspace.id))
    }

    func testMissingFolderProducesErrorAndClearsRunningState() async {
        let store = GitHubScanStore()
        let missing = tempDir().appendingPathComponent("missing")
        let workspace = Workspace(name: "Missing", rootPath: missing.path, tabs: [TerminalTab(title: "shell")])

        store.scan(workspace: workspace)
        await waitForScan(store, workspaceId: workspace.id)

        XCTAssertEqual(store.result(for: workspace.id)?.error, "Workspace folder no longer exists.")
        XCTAssertFalse(store.runningWorkspaceIds.contains(workspace.id))
    }

    func testNonGitFolderProducesError() async throws {
        let store = GitHubScanStore()
        let dir = tempDir()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let workspace = Workspace(name: "Plain", rootPath: dir.path, tabs: [TerminalTab(title: "shell")])

        store.scan(workspace: workspace)
        await waitForScan(store, workspaceId: workspace.id)

        XCTAssertEqual(store.result(for: workspace.id)?.error, "No Git repository found.")
    }

    func testSuccessfulRepositoryScanParsesBranchStatusAndCommits() async throws {
        let store = GitHubScanStore()
        let repo = tempDir()
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init"], cwd: repo)
        try runGit(["config", "user.email", "test@example.com"], cwd: repo)
        try runGit(["config", "user.name", "in0 Tests"], cwd: repo)
        try "hello\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], cwd: repo)
        try runGit(["commit", "-m", "Initial commit"], cwd: repo)
        try "changed\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "new\n".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
        let workspace = Workspace(name: "Repo", rootPath: repo.path, tabs: [TerminalTab(title: "shell")])

        store.scan(workspace: workspace)
        store.scan(workspace: workspace)
        XCTAssertTrue(store.runningWorkspaceIds.contains(workspace.id))
        await waitForScan(store, workspaceId: workspace.id)

        let result = try XCTUnwrap(store.result(for: workspace.id))
        XCTAssertNil(result.error)
        XCTAssertEqual(normalizedTmpPath(result.rootPath), normalizedTmpPath(repo.path))
        XCTAssertFalse(result.branch.isEmpty)
        XCTAssertEqual(result.statusSummary, "modified 1 · untracked 1")
        XCTAssertTrue(result.checks.contains("Git repository found"))
        XCTAssertTrue(result.checks.contains("Modified files need review"))
        XCTAssertTrue(result.checks.contains("Untracked files need review"))
        XCTAssertTrue(result.recentCommits.contains { $0.contains("Initial commit") })
        XCTAssertFalse(store.runningWorkspaceIds.contains(workspace.id))
    }

    private func tempDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("in0-github-scan-\(UUID().uuidString)", isDirectory: true)
        tmpDirs.append(dir)
        return dir
    }

    private func waitForScan(_ store: GitHubScanStore, workspaceId: UUID) async {
        for _ in 0..<100 where store.runningWorkspaceIds.contains(workspaceId) {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func runGit(_ args: [String], cwd: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = cwd
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            XCTFail("git \(args.joined(separator: " ")) failed: \(output)")
            return
        }
    }

    private func normalizedTmpPath(_ path: String) -> String {
        path.replacingOccurrences(of: "/private/var/", with: "/var/")
    }
}
