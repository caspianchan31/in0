import Foundation

/// Stable identifier for a quick action. Built-ins use their enum raw value
/// (`"gitui"`, `"claude"`, ...); custom actions use a UUID string created
/// on insert.
typealias QuickActionId = String

/// First-class actions that ship with in0. Each has a default command (the
/// user can override per-action via `QuickActionsStore.setBuiltinCommand`),
/// a localized display name, and a fixed icon source.
enum BuiltinQuickAction: String, CaseIterable, Identifiable {
    case gitui
    case claude
    case codex
    case opencode

    var id: QuickActionId { rawValue }

    /// Shell command to run when this action launches a new tab. Override
    /// via `QuickActionsStore.setBuiltinCommand`.
    var defaultCommand: String {
        switch self {
        case .gitui:    return "gitui"
        case .claude:   return "claude"
        case .codex:    return "codex"
        case .opencode: return "opencode"
        }
    }

    var displayName: LocalizedStringResource {
        switch self {
        case .gitui:    return L10n.QuickActions.Builtin.gitui
        case .claude:   return L10n.QuickActions.Builtin.claude
        case .codex:    return L10n.QuickActions.Builtin.codex
        case .opencode: return L10n.QuickActions.Builtin.opencode
        }
    }

    /// Render hint for the icon. Custom actions fall back to `.letter`.
    var iconSource: QuickActionIcon {
        switch self {
        case .gitui:    return .sfSymbol("arrow.branch")
        case .claude:   return .asset("quick-action-claudecode")
        case .codex:    return .asset("quick-action-codex")
        case .opencode: return .asset("quick-action-opencode")
        }
    }

    /// nil if `id` doesn't name a built-in (likely a custom UUID).
    static func from(id: QuickActionId) -> BuiltinQuickAction? {
        BuiltinQuickAction(rawValue: id)
    }
}

/// User-defined action. Persisted as JSON inside the in0 config file via
/// `QuickActionsStore`. The visual order is owned by the store's
/// `orderedIds`, not this struct.
struct CustomQuickAction: Codable, Identifiable, Equatable {
    let id: QuickActionId
    var name: String
    var command: String
}

/// Discriminator for icon rendering. The view layer (`QuickActionIconView`)
/// switches on this.
enum QuickActionIcon: Equatable {
    /// SF Symbol name → `NSImage(systemSymbolName:)` / `Image(systemName:)`.
    case sfSymbol(String)
    /// Asset catalog name → `NSImage(named:)` / `Image(_:)`.
    case asset(String)
    /// Single-letter chip — fallback for custom actions, computed from the
    /// first letter of the user-entered name.
    case letter(Character)
}
