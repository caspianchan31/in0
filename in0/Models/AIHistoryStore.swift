import Foundation
import Observation

struct AIHistoryEntry: Equatable, Identifiable, Sendable {
    var id: String { relativePath }
    var agent: String
    var title: String
    var relativePath: String
    var modifiedAt: Date
    var snippet: String
    var resumeCommand: String?
}

struct AIHistoryResult: Equatable, Sendable {
    var rootPath: String
    var entries: [AIHistoryEntry]
    var scannedAt: Date
    var error: String?

    static func empty(rootPath: String?, error: String? = nil) -> AIHistoryResult {
        AIHistoryResult(
            rootPath: rootPath ?? "No workspace folder",
            entries: [],
            scannedAt: Date(),
            error: error
        )
    }
}

@MainActor
@Observable
final class AIHistoryStore {
    private(set) var results: [UUID: AIHistoryResult] = [:]
    private(set) var runningWorkspaceIds: Set<UUID> = []

    func result(for workspaceId: UUID) -> AIHistoryResult? {
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
            let result = Self.performScan(rootPath: rootPath)
            await MainActor.run {
                self.results[workspace.id] = result
                self.runningWorkspaceIds.remove(workspace.id)
            }
        }
    }

    nonisolated static func performScan(rootPath: String, homePath: String = NSHomeDirectory()) -> AIHistoryResult {
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let home = URL(fileURLWithPath: homePath, isDirectory: true).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            return .empty(rootPath: rootPath, error: "Workspace folder no longer exists.")
        }

        let urls = candidateFiles(in: root, home: home)
        let entries = urls.compactMap { entry(for: $0, root: root) }
            .sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }

        return AIHistoryResult(
            rootPath: root.path,
            entries: Array(entries.prefix(20)),
            scannedAt: Date(),
            error: entries.isEmpty ? "No AI history files found in this workspace." : nil
        )
    }

    private nonisolated static func candidateFiles(in root: URL, home: URL) -> [URL] {
        let roots = [
            ".claude",
            ".codex",
            ".opencode",
            ".in0/ai-history",
            "ai-history",
        ].map { root.appendingPathComponent($0, isDirectory: true) }

        var output: [URL] = []
        for candidateRoot in roots {
            output.append(contentsOf: files(
                under: candidateRoot,
                root: root,
                includeAllText: true,
                requireInsideWorkspace: true
            ))
        }
        output.append(contentsOf: files(under: root, root: root, includeAllText: false, requireInsideWorkspace: true))
        output.append(contentsOf: globalCandidateFiles(for: root, home: home))

        var seen = Set<String>()
        return output.filter { url in
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private nonisolated static func globalCandidateFiles(for root: URL, home: URL) -> [URL] {
        let roots = [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".codex/archived_sessions", isDirectory: true),
            home.appendingPathComponent(".opencode", isDirectory: true),
        ]

        var output: [URL] = []
        for candidateRoot in roots {
            output.append(contentsOf: files(
                under: candidateRoot,
                root: root,
                includeAllText: true,
                requireInsideWorkspace: false
            ))
        }
        return output
    }

    private nonisolated static func files(
        under directory: URL,
        root: URL,
        includeAllText: Bool,
        requireInsideWorkspace: Bool
    ) -> [URL] {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir), isDir.boolValue else {
            return []
        }

        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator {
            if requireInsideWorkspace {
                guard isInsideWorkspace(url, root: root) else { continue }
            }
            if shouldSkipDirectory(url) {
                enumerator.skipDescendants()
                continue
            }
            guard isCandidateFile(url, includeAllText: includeAllText) else { continue }
            let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            candidates.append((url, modifiedAt))
        }
        return candidates
            .sorted { lhs, rhs in lhs.modifiedAt > rhs.modifiedAt }
            .prefix(requireInsideWorkspace ? 80 : 800)
            .map(\.url)
    }

    private nonisolated static func entry(for url: URL, root: URL) -> AIHistoryEntry? {
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modifiedAt = values.contentModificationDate else { return nil }
        if let size = values.fileSize, size > 512 * 1024 { return nil }
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let text = String(data: data.prefix(128 * 1024), encoding: .utf8) else { return nil }

        let relativePath = relativePath(for: url, root: root)
        guard !isKnownConfigFile(relativePath: relativePath, url: url) else { return nil }
        guard isInsideWorkspace(url, root: root) || globalSessionMatchesWorkspace(text: text, root: root) else { return nil }

        let snippet = normalizedSnippet(from: text)
        guard !snippet.isEmpty else { return nil }

        return AIHistoryEntry(
            agent: agentName(for: relativePath),
            title: title(for: url, fallback: snippet, text: text),
            relativePath: relativePath,
            modifiedAt: modifiedAt,
            snippet: snippet,
            resumeCommand: resumeCommand(for: url, relativePath: relativePath, text: text)
        )
    }

    private nonisolated static func isCandidateFile(_ url: URL, includeAllText: Bool) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["json", "jsonl", "md", "markdown", "txt", "log"].contains(ext) else { return false }
        if includeAllText { return true }

        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        return ["history", "conversation", "conversations", "transcript", "session", "chat"]
            .contains { name.contains($0) }
    }

    private nonisolated static func shouldSkipDirectory(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        return ["node_modules", ".git", ".build", "DerivedData", "vendor"].contains(url.lastPathComponent)
    }

    private nonisolated static func isInsideWorkspace(_ url: URL, root: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }

    private nonisolated static func relativePath(for url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).standardizedFileURL.path
            if path.hasPrefix(home + "/") {
                return "~/" + String(path.dropFirst(home.count + 1))
            }
            return path
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private nonisolated static func agentName(for relativePath: String) -> String {
        let lower = relativePath.lowercased()
        if lower.contains(".claude") || lower.contains("claude") { return "Claude" }
        if lower.contains(".codex") || lower.contains("codex") { return "Codex" }
        if lower.contains(".opencode") || lower.contains("opencode") { return "OpenCode" }
        return "AI"
    }

    private nonisolated static func title(for url: URL, fallback: String, text: String) -> String {
        if let title = firstJSONStringValue(in: text, keys: ["thread_name", "title"]),
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, name.lowercased() != "history" { return name }
        return String(fallback.prefix(48))
    }

    private nonisolated static func normalizedSnippet(from text: String) -> String {
        text
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let cleaned = line
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"[\{\}\[\]"]"#, with: " ", options: .regularExpression)
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return cleaned.isEmpty ? nil : cleaned
            }
            .prefix(6)
            .joined(separator: " ")
    }

    private nonisolated static func resumeCommand(for url: URL, relativePath: String, text: String) -> String? {
        let lower = relativePath.lowercased()
        let sessionId = sessionId(from: text)
            ?? codexSessionId(from: text)
            ?? sessionId(fromFileName: url, relativePath: relativePath)
        guard let sessionId else { return nil }

        if lower.contains(".codex") || lower.contains("codex") {
            return "codex resume \(sessionId)"
        }
        if lower.contains(".claude") || lower.contains("claude") {
            return "claude --resume \(sessionId)"
        }
        if lower.contains(".opencode") || lower.contains("opencode") {
            return "opencode --resume \(sessionId)"
        }
        return nil
    }

    private nonisolated static func isKnownConfigFile(relativePath: String, url: URL) -> Bool {
        let lowerPath = relativePath.lowercased()
        let basename = url.deletingPathExtension().lastPathComponent.lowercased()
        if ["settings", "settings.local", "config", "config.local", "preferences", "hooks"].contains(basename) {
            return true
        }
        return lowerPath.hasSuffix("/settings.json")
            || lowerPath.hasSuffix("/settings.local.json")
            || lowerPath.hasSuffix("/config.json")
            || lowerPath.hasSuffix("/hooks.json")
    }

    private nonisolated static func sessionId(from text: String) -> String? {
        for value in jsonStringValues(in: text, keys: ["sessionId", "session_id", "conversationId", "conversation_id"]) {
            if isSessionLike(value) { return value }
        }
        return nil
    }

    private nonisolated static func codexSessionId(from text: String) -> String? {
        for value in jsonStringValues(in: text, keys: ["id"]) {
            if isCodexSessionId(value) { return value }
        }
        return nil
    }

    private nonisolated static func firstJSONStringValue(in text: String, keys: [String]) -> String? {
        jsonStringValues(in: text, keys: keys).first
    }

    private nonisolated static func jsonStringValues(in text: String, keys: [String]) -> [String] {
        let patterns = keys.map { #""\#($0)"\s*:\s*"([^"]+)""# }
        var values: [String] = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard match.numberOfRanges > 1,
                      let valueRange = Range(match.range(at: 1), in: text) else { continue }
                values.append(String(text[valueRange]))
            }
        }
        return values
    }

    private nonisolated static func sessionId(fromFileName url: URL, relativePath: String) -> String? {
        guard allowsFilenameResumeFallback(relativePath: relativePath) else { return nil }
        let name = url.deletingPathExtension().lastPathComponent
        return isSessionLike(name) ? name : nil
    }

    private nonisolated static func allowsFilenameResumeFallback(relativePath: String) -> Bool {
        let components = relativePath
            .lowercased()
            .split(separator: "/")
            .map(String.init)
        return components.contains("sessions")
            || components.contains("session")
            || components.contains("conversations")
            || components.contains("transcripts")
    }

    private nonisolated static func isSessionLike(_ value: String) -> Bool {
        guard value.count >= 8 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private nonisolated static func isCodexSessionId(_ value: String) -> Bool {
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private nonisolated static func globalSessionMatchesWorkspace(text: String, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        for cwd in jsonStringValues(in: text, keys: ["cwd"]) {
            let normalizedCwd = URL(fileURLWithPath: cwd, isDirectory: true).standardizedFileURL.path
            if rootPath == normalizedCwd
                || rootPath.hasPrefix(normalizedCwd + "/")
                || normalizedCwd.hasPrefix(rootPath + "/") {
                return true
            }
        }
        return text.contains(rootPath)
    }
}
