import Foundation
import Observation

/// Strongly-typed facade over `SettingsConfigStore`. The config file is the
/// single source of truth — `SettingsStore` exists only so the rest of the
/// code (`HookDispatcher`, `SettingsView`, `ThemeManager` hook) gets typed
/// accessors rather than scattering raw `configStore.get("...")` calls.
///
/// Every setter funnels through `SettingsConfigStore.set(_:_:)`, which
/// debounces + writes the change to disk and posts `onChange` so the
/// chrome / theme / quick actions can hot-reload. Defaults reflect the
/// values used when the key is absent from the file; writing the default
/// removes the key (configs stay minimal, only user overrides live on
/// disk).
@MainActor
@Observable
final class SettingsStore {
    struct AgentPrefs: Equatable {
        var notificationsEnabled: Bool
        var resumeOnLaunch: Bool
    }

    struct Snapshot: Equatable {
        var claude: AgentPrefs
        var codex: AgentPrefs
        var opencode: AgentPrefs
        var followsTerminalBackground: Bool
        var statusIndicatorsEnabled: Bool
        var fontFamily: String
        var fontSize: Int
        var shellOverride: String
        var themeName: String
        var languageChoice: String
    }

    let configStore: SettingsConfigStore

    init(configStore: SettingsConfigStore) {
        self.configStore = configStore
    }

    /// Materialize the current snapshot from the config file. Recomputed
    /// every read because the underlying lines may change underneath us
    /// (out-of-band edits, agent toggles, etc.) — cost is negligible (a
    /// dozen array scans against a list that's effectively under 100 lines).
    var snapshot: Snapshot {
        Snapshot(
            claude:   prefs(for: .claude),
            codex:    prefs(for: .codex),
            opencode: prefs(for: .opencode),
            followsTerminalBackground: boolValue(Self.kFollowsBg, default: true),
            statusIndicatorsEnabled:   boolValue(Self.kStatusIndicators, default: true),
            fontFamily:     configStore.get(Self.kFontFamily) ?? "",
            fontSize:       intValue(Self.kFontSize, default: 13),
            shellOverride:  configStore.get(Self.kShell) ?? "",
            themeName:      configStore.get(Self.kTheme) ?? "",
            languageChoice: configStore.get(Self.kLanguage) ?? "system"
        )
    }

    func prefs(for agent: HookAgent) -> AgentPrefs {
        AgentPrefs(
            notificationsEnabled: boolValue(Self.notifKey(agent), default: Self.defaultNotifications(agent)),
            resumeOnLaunch:       boolValue(Self.resumeKey(agent), default: true)
        )
    }

    func setNotifications(_ on: Bool, for agent: HookAgent) {
        writeBool(Self.notifKey(agent), value: on, default: Self.defaultNotifications(agent))
    }
    func setResumeOnLaunch(_ on: Bool, for agent: HookAgent) {
        writeBool(Self.resumeKey(agent), value: on, default: true)
    }

    func setFollowsTerminalBackground(_ on: Bool) { writeBool(Self.kFollowsBg, value: on, default: true) }
    func setStatusIndicatorsEnabled(_ on: Bool) { writeBool(Self.kStatusIndicators, value: on, default: true) }
    func setFontFamily(_ value: String) { writeString(Self.kFontFamily, value: value) }
    func setFontSize(_ value: Int) {
        let clamped = max(8, min(32, value))
        if clamped == 13 { configStore.set(Self.kFontSize, nil) }
        else             { configStore.set(Self.kFontSize, String(clamped)) }
    }
    func setShellOverride(_ value: String) { writeString(Self.kShell, value: value) }
    func setGitViewerCommand(_ value: String) { writeString(Self.kGitViewer, value: value) }
    var gitViewerCommand: String {
        configStore.get(Self.kGitViewer) ?? "gitui"
    }
    func setThemeName(_ value: String)     { writeString(Self.kTheme, value: value) }
    func setLanguageChoice(_ value: String) {
        if value == "system" { configStore.set(Self.kLanguage, nil) }
        else                 { configStore.set(Self.kLanguage, value) }
    }

    // MARK: - Key constants

    private static let kFollowsBg       = "follows-terminal-background"
    private static let kStatusIndicators = "status-indicators-enabled"
    private static let kFontFamily = "font-family"
    private static let kFontSize   = "font-size"
    private static let kShell      = "command"
    private static let kGitViewer  = "in0-git-viewer"
    private static let kTheme      = "theme"
    private static let kLanguage   = "language"

    private static func notifKey(_ agent: HookAgent) -> String { "agent-\(agent.rawValue)-notifications" }
    private static func resumeKey(_ agent: HookAgent) -> String { "agent-\(agent.rawValue)-resume" }

    /// Claude's notification stream doubles as a 60s heartbeat, so we keep
    /// it OFF by default to avoid clobbering `.finished` states. Codex and
    /// OpenCode default ON.
    private static func defaultNotifications(_ agent: HookAgent) -> Bool {
        switch agent {
        case .claude: return false
        case .codex, .opencode: return true
        }
    }

    // MARK: - Coercion helpers

    private func boolValue(_ key: String, default defaultValue: Bool) -> Bool {
        guard let raw = configStore.get(key) else { return defaultValue }
        return raw.lowercased() == "true"
    }
    private func intValue(_ key: String, default defaultValue: Int) -> Int {
        guard let raw = configStore.get(key), let v = Int(raw) else { return defaultValue }
        return v
    }
    private func writeBool(_ key: String, value: Bool, default defaultValue: Bool) {
        if value == defaultValue { configStore.set(key, nil) }
        else                     { configStore.set(key, value ? "true" : "false") }
    }
    private func writeString(_ key: String, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        configStore.set(key, trimmed.isEmpty ? nil : trimmed)
    }
}
