import Foundation
import Observation

/// Polls git branch for every workspace's focused terminal pwd every 5
/// seconds. Writes results into `WorkspaceMetadataStore`.
@MainActor
final class MetadataRefresher {
    private let workspaces: WorkspaceStore
    private let pwds: TerminalPwdStore
    private let metadata: WorkspaceMetadataStore
    private var timer: DispatchSourceTimer?

    /// Optional fan-out invoked on the main actor after each tick's
    /// metadata write completes. Tests subscribe to wait for the
    /// asynchronous write-back without sleeping; production has no
    /// consumer (SwiftUI observes the @Observable store directly).
    var onRefresh: (() -> Void)?

    init(workspaces: WorkspaceStore, pwds: TerminalPwdStore, metadata: WorkspaceMetadataStore) {
        self.workspaces = workspaces
        self.pwds = pwds
        self.metadata = metadata
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
        for ws in workspaces.workspaces {
            guard let tabId = ws.selectedTabId,
                  let tab = ws.tabs.first(where: { $0.id == tabId }) else { continue }
            let pwd = pwds.pwd(for: tab.focusedTerminalId)
            // Run git in background; keep UI responsive.
            let wsId = ws.id
            let store = self.metadata
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let branch = pwd.flatMap(Self.gitBranch(at:))
                let prCount = pwd.flatMap(Self.openPRCount(at:))
                DispatchQueue.main.async {
                    let prStatus: String? = {
                        guard let n = prCount, n > 0 else { return nil }
                        return n == 1 ? "1 PR" : "\(n) PRs"
                    }()
                    store.set(
                        WorkspaceMetadataSnapshot(
                            gitBranch: branch,
                            pwd: pwd,
                            openPRCount: prCount,
                            unreadNotifications: nil,
                            prStatus: prStatus,
                            updatedAt: Date()
                        ),
                        for: wsId
                    )
                    self?.onRefresh?()
                }
            }
        }
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
