import Foundation

/// The settings categories. Display order matches this enum order —
/// Quick Actions, Plugins, and Agents sit near the top because they're used
/// far more than Font / Terminal / Shell day-to-day.
enum SettingsSection: String, CaseIterable, Identifiable {
    case appearance
    case quickActions
    case plugins
    case agents
    case font
    case terminal
    case shell
    case update

    var id: String { rawValue }

    var label: LocalizedStringResource {
        switch self {
        case .appearance:   return L10n.Settings.sectionAppearance
        case .font:         return L10n.Settings.sectionFont
        case .terminal:     return L10n.Settings.sectionTerminal
        case .shell:        return L10n.Settings.sectionShell
        case .quickActions: return L10n.Settings.sectionQuickActions
        case .plugins:      return L10n.Settings.sectionPlugins
        case .agents:       return L10n.Settings.sectionAgents
        case .update:       return L10n.Settings.sectionUpdate
        }
    }

    var sfSymbol: String {
        switch self {
        case .appearance:   return "paintbrush"
        case .font:         return "textformat"
        case .terminal:     return "terminal"
        case .shell:        return "command"
        case .quickActions: return "bolt"
        case .plugins:      return "puzzlepiece.extension"
        case .agents:       return "wand.and.rays"
        case .update:       return "arrow.triangle.2.circlepath"
        }
    }
}
