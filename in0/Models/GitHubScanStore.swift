import Foundation
import Observation

struct GitHubScanResult: Equatable, Sendable {
    var rootPath: String
    var branch: String
    var remote: String
    var statusSummary: String
    var checks: [String]
    var recentCommits: [String]
    var scannedAt: Date
    var error: String?

    static func empty(rootPath: String?, error: String? = nil) -> GitHubScanResult {
        GitHubScanResult(
            rootPath: rootPath ?? "No workspace folder",
            branch: "-",
            remote: "-",
            statusSummary: "-",
            checks: [],
            recentCommits: [],
            scannedAt: Date(),
            error: error
        )
    }
}

@MainActor
@Observable
final class GitHubScanStore {
    private(set) var results: [UUID: GitHubScanResult] = [:]
    private(set) var runningWorkspaceIds: Set<UUID> = []

    func result(for workspaceId: UUID) -> GitHubScanResult? {
        results[workspaceId]
    }

    func scan(workspace: Workspace) {
        guard !runningWorkspaceIds.contains(workspace.id) else { return }
        guard let rootPath = workspace.rootPath else {
            results[workspace.id] = .empty(rootPath: nil, error: "Choose a folder for this workspace first.")
            return
        }
        runningWorkspaceIds.insert(workspace.id)
        Task.detached(priority: .utility) {
            let result = await Self.performScan(rootPath: rootPath)
            await MainActor.run {
                self.results[workspace.id] = result
                self.runningWorkspaceIds.remove(workspace.id)
            }
        }
    }

    private static func performScan(rootPath: String) async -> GitHubScanResult {
        guard FileManager.default.fileExists(atPath: rootPath) else {
            return .empty(rootPath: rootPath, error: "Workspace folder no longer exists.")
        }
        let root = runGit(["rev-parse", "--show-toplevel"], cwd: rootPath)
        guard root.exitCode == 0 else {
            return .empty(rootPath: rootPath, error: "No Git repository found.")
        }
        let branch = runGit(["branch", "--show-current"], cwd: rootPath).output.trimmedNonEmpty ?? "detached"
        let remotes = runGit(["remote", "-v"], cwd: rootPath).output
            .split(separator: "\n")
            .first
            .map(String.init) ?? "-"
        let statusLines = runGit(["status", "--short"], cwd: rootPath).output
            .split(separator: "\n")
        let modified = statusLines.filter { !$0.hasPrefix("??") }.count
        let untracked = statusLines.filter { $0.hasPrefix("??") }.count
        let commits = runGit(["log", "--oneline", "-8"], cwd: rootPath).output
            .split(separator: "\n")
            .map(String.init)
        var checks = ["Git repository found"]
        if remotes != "-" { checks.append("Remote configured") }
        if untracked > 0 { checks.append("Untracked files need review") }
        if modified > 0 { checks.append("Modified files need review") }
        return GitHubScanResult(
            rootPath: root.output.trimmingCharacters(in: .whitespacesAndNewlines),
            branch: branch,
            remote: remotes,
            statusSummary: "modified \(modified) · untracked \(untracked)",
            checks: checks,
            recentCommits: commits,
            scannedAt: Date(),
            error: nil
        )
    }

    private static func runGit(_ args: [String], cwd: String) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (1, String(describing: error))
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
