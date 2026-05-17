import Foundation
import Observation

/// Polls git branch for every workspace's focused terminal pwd every 5
/// seconds. Writes results into `WorkspaceMetadataStore`.
@MainActor
final class MetadataRefresher {
    private struct Request {
        let workspaceId: UUID
        let pwd: String?
    }

    private struct ResolvedMetadata {
        let gitBranch: String?
        let openPRCount: Int?
    }

    private let workspaces: WorkspaceStore
    private let pwds: TerminalPwdStore
    private let metadata: WorkspaceMetadataStore
    private let branchResolver: @Sendable (String) -> String?
    private let prCountResolver: @Sendable (String) -> Int?
    private var timer: DispatchSourceTimer?

    /// Optional fan-out invoked on the main actor after each tick's
    /// metadata write completes. Tests subscribe to wait for the
    /// asynchronous write-back without sleeping; production has no
    /// consumer (SwiftUI observes the @Observable store directly).
    var onRefresh: (() -> Void)?

    init(
        workspaces: WorkspaceStore,
        pwds: TerminalPwdStore,
        metadata: WorkspaceMetadataStore,
        branchResolver: @escaping @Sendable (String) -> String? = { MetadataRefresher.gitBranch(at: $0) },
        prCountResolver: @escaping @Sendable (String) -> Int? = { MetadataRefresher.openPRCount(at: $0) }
    ) {
        self.workspaces = workspaces
        self.pwds = pwds
        self.metadata = metadata
        self.branchResolver = branchResolver
        self.prCountResolver = prCountResolver
    }

    func start(interval: TimeInterval = 5.0) {
        stop()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + .seconds(1), repeating: interval)
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let requests = workspaces.workspaces.compactMap { ws -> Request? in
            guard let tabId = ws.selectedTabId,
                  let tab = ws.tabs.first(where: { $0.id == tabId }) else { return nil }
            return Request(workspaceId: ws.id, pwd: pwds.pwd(for: tab.focusedTerminalId))
        }
        guard !requests.isEmpty else { return }

        let store = self.metadata
        let branchResolver = self.branchResolver
        let prCountResolver = self.prCountResolver

        DispatchQueue.global(qos: .utility).async { [weak self] in
            let uniquePwds = Set(requests.compactMap(\.pwd))
            let resolvedByPwd = uniquePwds.reduce(into: [String: ResolvedMetadata]()) { output, pwd in
                output[pwd] = ResolvedMetadata(
                    gitBranch: branchResolver(pwd),
                    openPRCount: prCountResolver(pwd)
                )
            }

            let now = Date()
            let snapshots = requests.reduce(into: [UUID: WorkspaceMetadataSnapshot]()) { output, request in
                let resolved = request.pwd.flatMap { resolvedByPwd[$0] }
                let prCount = resolved?.openPRCount
                output[request.workspaceId] = WorkspaceMetadataSnapshot(
                    gitBranch: resolved?.gitBranch,
                    pwd: request.pwd,
                    openPRCount: prCount,
                    unreadNotifications: nil,
                    prStatus: Self.prStatus(for: prCount),
                    updatedAt: now
                )
            }

            DispatchQueue.main.async {
                store.set(snapshots)
                self?.onRefresh?()
            }
        }
    }

    nonisolated static func prStatus(for count: Int?) -> String? {
        guard let count, count > 0 else { return nil }
        return count == 1 ? "1 PR" : "\(count) PRs"
    }

    /// Best-effort `gh pr list --json number --jq 'length'`. Returns nil if
    /// `gh` is missing, the path isn't a repo, or the call fails.
    private nonisolated static func openPRCount(at path: String) -> Int? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let gh = "/opt/homebrew/bin/gh"
        guard FileManager.default.isExecutableFile(atPath: gh) else { return nil }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: gh)
        task.arguments = ["-C", path, "pr", "list", "--state", "open", "--json", "number", "--jq", "length"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let raw = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return raw.flatMap(Int.init)
        } catch { return nil }
    }

    /// Parse a `git rev-parse --abbrev-ref HEAD` output line. Public so
    /// tests can verify trimming + empty-output handling without spawning
    /// a real git process.
    nonisolated static func parseBranch(from output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Best-effort `git rev-parse --abbrev-ref HEAD`. Returns nil on any
    /// failure (not a repo, git not installed, path missing, etc.).
    private nonisolated static func gitBranch(at path: String) -> String? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw : nil
        } catch {
            return nil
        }
    }
}
