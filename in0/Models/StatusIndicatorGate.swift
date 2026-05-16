import Foundation

/// Pure derivation: should the chrome show terminal status indicators
/// at all? Two layers:
///
/// 1. The global `status-indicators-enabled` toggle (Settings ▸
///    Appearance). Defaults true; user can hard-disable.
/// 2. At least one agent toggle on (Settings ▸ Agents). If the user
///    has every agent off, there's nothing to show — render no icons
///    even when the global toggle is on.
///
/// Kept as a pure namespace so tests can fuzz the gate without spinning
/// up a real `SettingsStore` snapshot — point them at a temp config
/// file and exercise the keys directly.
enum StatusIndicatorGate {
    /// Returns true when at least one agent has notifications enabled in
    /// the supplied `SettingsConfigStore`. Honors the legacy bypass: a
    /// stray `status-indicators` line from before the per-agent split
    /// must NOT resurrect the feature on its own — only per-agent keys
    /// count.
    @MainActor
    static func anyAgentEnabled(_ settings: SettingsConfigStore) -> Bool {
        for agent in HookAgent.allCases {
            let key = "agent-\(agent.rawValue)-notifications"
            // Mirror SettingsStore's per-agent default: false for claude,
            // true for codex/opencode (Claude's Notification hook is a
            // 60 s heartbeat, intentionally muted by default).
            let `default` = (agent == .claude) ? false : true
            let raw = settings.get(key)
            let enabled = raw.flatMap { $0.lowercased() == "true" } ?? `default`
            if enabled { return true }
        }
        return false
    }
}
