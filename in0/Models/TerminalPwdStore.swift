import Foundation
import Observation

/// terminalId → current working directory. Updated whenever ghostty fires
/// the PWD action (driven by OSC 7 from shell integration). Persisted to
/// UserDefaults with a 300 ms debounce so a tight `cd` loop doesn't write
/// on every keystroke.
@MainActor
@Observable
final class TerminalPwdStore {
    static let defaultPersistenceKey = "in0.pwds.v1"

    /// Singleton accessor used by call sites that can't reach the
    /// SwiftUI environment (e.g. `GhosttyTerminalView` consulting the
    /// inherited pwd at surface-spawn time). `in0App` wires this same
    /// instance into the environment, so SwiftUI and the singleton are
    /// identical at runtime.
    static let shared = TerminalPwdStore()

    private let persistenceKey: String
    private(set) var pwds: [UUID: String]
    private var saveTimer: DispatchSourceTimer?

    init(persistenceKey: String = TerminalPwdStore.defaultPersistenceKey) {
        self.persistenceKey = persistenceKey
        self.pwds = Self.load(persistenceKey: persistenceKey)
    }

    func setPwd(_ pwd: String, for terminalId: UUID) {
        guard pwds[terminalId] != pwd else { return }
        pwds[terminalId] = pwd
        scheduleSave()
    }

    func pwd(for terminalId: UUID) -> String? {
        pwds[terminalId]
    }

    /// Copy `from`'s pwd onto `to`. No-op when `from` has no pwd. Used
    /// when splitting a pane so the new shell inherits the parent's cwd
    /// instead of starting at $HOME.
    func inherit(from src: UUID, to dst: UUID) {
        guard let pwd = pwds[src] else { return }
        setPwd(pwd, for: dst)
    }

    /// Drop the entry for a closed terminal so dead UUIDs don't bloat
    /// the persisted dict over time.
    func forget(terminalId: UUID) {
        pwds.removeValue(forKey: terminalId)
        scheduleSave()
    }

    /// Snapshot used by SidebarListBridge to feed metadata to the AppKit
    /// row views without exposing the @Observable property directly.
    func pwdsSnapshot() -> [UUID: String] { pwds }

    /// Skip the debounce — used in tests. No-op in production.
    func flushSaveForTesting() {
        saveTimer?.cancel()
        saveTimer = nil
        save()
    }

    /// Legacy alias retained so existing call sites that used `remove`
    /// keep compiling. `forget` is the preferred name.
    func remove(_ terminalId: UUID) { forget(terminalId: terminalId) }

    private func scheduleSave() {
        saveTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(300))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.save() }
        }
        timer.resume()
        saveTimer = timer
    }

    private func save() {
        let dict = pwds.reduce(into: [String: String]()) {
            $0[$1.key.uuidString] = $1.value
        }
        UserDefaults.standard.set(dict, forKey: persistenceKey)
    }

    private static func load(persistenceKey: String) -> [UUID: String] {
        guard let raw = UserDefaults.standard.dictionary(forKey: persistenceKey) as? [String: String]
        else { return [:] }
        var out: [UUID: String] = [:]
        for (k, v) in raw where UUID(uuidString: k) != nil {
            out[UUID(uuidString: k)!] = v
        }
        return out
    }
}
