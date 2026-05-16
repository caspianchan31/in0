import AppKit
import Foundation
import Observation

/// Line-level representation of the in0 config file. Comments, blank lines,
/// and unknown rows round-trip unchanged so the user's hand edits aren't
/// lost when the app saves through the same file.
enum ConfigLine: Equatable {
    case comment(String)        // entire raw line including leading `#`
    case blank
    case kv(key: String, value: String)
    case unknown(String)        // line with no `=` — preserved verbatim
}

/// Reads and writes the in0 config file at
/// `~/Library/Application Support/in0/config`. The on-disk format is the
/// same `key = value` syntax ghostty's own config uses, so power users can
/// keep one mental model.
///
/// **Two write paths:**
/// - `set(key, value)` debounces 200 ms — for typed input where firing on
///   every keystroke would thrash both disk and any downstream reload.
/// - `setLive(key, value)` throttles 50 ms (leading + trailing edge) — for
///   sliders that need continuous visual feedback during drag.
///
/// **No-op short-circuit.** Both paths return immediately when the call
/// wouldn't change `lines` (writing the same value twice, deleting a key
/// that's absent). SwiftUI's `Binding` setters fire on every focus change;
/// without this guard each focus toggle would trigger a write, an
/// `onChange` callback, a config reload, a theme refresh, and finally a
/// view rebuild — which steals focus from the TextField that just lost it.
@MainActor
@Observable
final class SettingsConfigStore {
    private(set) var lines: [ConfigLine] = []
    private let filePath: String
    private var writeTask: Task<Void, Never>?
    private var liveLastFlush: Date = .distantPast
    private var liveTrailingTask: Task<Void, Never>?

    /// 50 ms = 20 Hz, enough headroom over a 60 Hz mouse stream to feel
    /// smooth while keeping the reload pipeline cheap.
    private static let liveInterval: TimeInterval = 0.05
    private static let debounceInterval: TimeInterval = 0.20

    /// Fired on the main actor after each write actually hits disk. Wire to
    /// ghostty `reloadConfig` + theme refresh so GUI edits flow into running
    /// surfaces. Sync `save()` (used by tests) does NOT trigger this.
    var onChange: (() -> Void)?

    static var defaultPath: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Application Support/in0/config"
    }

    init(filePath: String = SettingsConfigStore.defaultPath) {
        self.filePath = filePath
        reload()
    }

    /// Read the file off disk, replacing in-memory `lines`. Absent file ⇒
    /// empty array; doesn't throw.
    func reload() {
        guard let contents = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            lines = []
            return
        }
        lines = Self.parse(contents)
    }

    /// First value bound to `key`, or nil when absent.
    func get(_ key: String) -> String? {
        for line in lines {
            if case .kv(let k, let v) = line, k == key { return v }
        }
        return nil
    }

    /// Set / overwrite / remove a value. nil removes the key. Debounced 200 ms.
    func set(_ key: String, _ value: String?) {
        guard updateLines(key: key, value: value) else { return }
        scheduleDebouncedWrite()
    }

    /// Same as `set` but with a 50 ms leading-edge throttle. Use for sliders.
    func setLive(_ key: String, _ value: String?) {
        guard updateLines(key: key, value: value) else { return }
        scheduleLiveWrite()
    }

    /// Synchronous flush (test path only — doesn't fire `onChange`).
    func save() {
        writeTask?.cancel()
        writeTask = nil
        liveTrailingTask?.cancel()
        liveTrailingTask = nil
        writeToDisk()
    }

    /// Make sure the file exists, then hand it to the user's default editor.
    func openInEditor() {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: filePath) {
            FileManager.default.createFile(atPath: filePath, contents: Data())
        }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Line-level mutations

    /// Mutates `lines` in place. Returns true when something actually
    /// changed; false otherwise so the caller can skip the write entirely.
    @discardableResult
    private func updateLines(key: String, value: String?) -> Bool {
        let idx = lines.firstIndex { line in
            if case .kv(let k, _) = line { return k == key }
            return false
        }

        if let idx {
            guard case .kv(_, let existing) = lines[idx] else { return false }
            if let value {
                if existing == value { return false }
                lines[idx] = .kv(key: key, value: value)
            } else {
                lines.remove(at: idx)
            }
            return true
        }

        guard let value else { return false }
        if let last = lines.last, case .blank = last {
            // already separated by a blank — append directly
        } else if !lines.isEmpty {
            lines.append(.blank)
        }
        lines.append(.kv(key: key, value: value))
        return true
    }

    // MARK: - Disk IO scheduling

    private func scheduleDebouncedWrite() {
        writeTask?.cancel()
        // A pending live trailing flush would overwrite our state moments
        // later; cancel it so we own the next disk hit.
        liveTrailingTask?.cancel()
        liveTrailingTask = nil
        writeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.debounceInterval * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.writeToDisk()
            self.liveLastFlush = Date()
            self.onChange?()
        }
    }

    private func scheduleLiveWrite() {
        let now = Date()
        let elapsed = now.timeIntervalSince(liveLastFlush)
        if elapsed >= Self.liveInterval {
            writeTask?.cancel()
            writeTask = nil
            liveTrailingTask?.cancel()
            liveTrailingTask = nil
            writeToDisk()
            liveLastFlush = Date()
            onChange?()
            return
        }
        if liveTrailingTask == nil {
            let delay = Self.liveInterval - elapsed
            liveTrailingTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                self.writeTask?.cancel()
                self.writeTask = nil
                self.liveTrailingTask = nil
                self.writeToDisk()
                self.liveLastFlush = Date()
                self.onChange?()
            }
        }
    }

    private func writeToDisk() {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let output = Self.serialize(lines)
        try? output.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Parse / serialize

    static func parse(_ contents: String) -> [ConfigLine] {
        var result: [ConfigLine] = []
        let raw = contents.components(separatedBy: "\n")
        let effective = (raw.last == "" ? Array(raw.dropLast()) : raw)
        for line in effective {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                result.append(.blank)
            } else if trimmed.hasPrefix("#") {
                result.append(.comment(line))
            } else if let eq = line.firstIndex(of: "=") {
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: eq)...])
                    .trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }
                result.append(.kv(key: key, value: value))
            } else {
                result.append(.unknown(line))
            }
        }
        return result
    }

    static func serialize(_ lines: [ConfigLine]) -> String {
        let rendered: [String] = lines.map { line in
            switch line {
            case .comment(let raw): return raw
            case .blank: return ""
            case .kv(let k, let v): return "\(k) = \(v)"
            case .unknown(let raw): return raw
            }
        }
        return rendered.joined(separator: "\n") + "\n"
    }

    // MARK: - Diagnostics (test helper)

    func debugCounts() -> (comments: Int, blanks: Int, unknowns: Int, kvs: Int) {
        var c = 0, b = 0, u = 0, k = 0
        for line in lines {
            switch line {
            case .comment: c += 1
            case .blank: b += 1
            case .unknown: u += 1
            case .kv: k += 1
            }
        }
        return (c, b, u, k)
    }
}
