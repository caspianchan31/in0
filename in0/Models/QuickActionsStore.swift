import Foundation
import Observation

/// Persistent state for the Quick Actions feature.
///
/// **Ordering model.** `orderedIds` is the single source of truth for
/// visual order across BOTH the top bar and the Settings list. Enable/
/// disable does NOT touch this array — a row keeps its position when the
/// switch flips, instead of jumping between an "enabled" and "disabled"
/// group. Only `reorderFull` / `reorderDisplay` / add / remove mutate it.
///
/// Persistence uses `SettingsConfigStore`, the same file that drives
/// ghostty-style config:
///
/// - `in0-quickactions-order`   — JSON array of all known ids, in display
///   order. Source of truth.
/// - `in0-quickactions-enabled` — JSON array of enabled ids. Membership
///   only; written in `orderedIds` order so file diffs are stable.
/// - `in0-quickactions-custom`  — JSON array of `CustomQuickAction`.
/// - `in0-quickactions-builtin-command-<id>` — only present when the user
///   has overridden a builtin's command.
///
/// Out-of-band edits to the config file should be picked up by calling
/// `reloadFromSettings()`; the host wires `SettingsConfigStore.onChange`
/// to that.
@MainActor
@Observable
final class QuickActionsStore {
    private(set) var orderedIds: [QuickActionId] = []
    private var enabledSet: Set<QuickActionId> = []
    private(set) var builtinCommandOverrides: [QuickActionId: String] = [:]
    private(set) var customActions: [CustomQuickAction] = []

    /// Backwards-compatible enabled-in-display-order view. Filters orphans
    /// (ids whose backing builtin/custom no longer exists).
    var enabledIds: [QuickActionId] {
        orderedIds.filter { enabledSet.contains($0) && exists($0) }
    }

    private let settings: SettingsConfigStore
    private let plugins: PluginStore?

    private static let kEnabled = "in0-quickactions-enabled"
    private static let kCustom  = "in0-quickactions-custom"
    private static let kOrder   = "in0-quickactions-order"
    private static func kBuiltinCmd(_ id: QuickActionId) -> String {
        "in0-quickactions-builtin-command-\(id)"
    }

    init(settings: SettingsConfigStore, plugins: PluginStore? = nil) {
        self.settings = settings
        self.plugins = plugins
        load()
    }

    // MARK: - Read

    func isEnabled(_ id: QuickActionId) -> Bool { enabledSet.contains(id) }

    private func exists(_ id: QuickActionId) -> Bool {
        BuiltinQuickAction.from(id: id) != nil
            || plugins?.actionDefinition(id) != nil
            || customActions.contains(where: { $0.id == id })
    }

    func isBuiltinAction(_ id: QuickActionId) -> Bool {
        BuiltinQuickAction.from(id: id) != nil
    }

    func isPluginAction(_ id: QuickActionId) -> Bool {
        plugins?.actionDefinition(id) != nil
    }

    func isCustomAction(_ id: QuickActionId) -> Bool {
        customActions.contains(where: { $0.id == id })
    }

    func defaultCommand(for id: QuickActionId) -> String? {
        if let builtin = BuiltinQuickAction.from(id: id) {
            return builtin.defaultCommand
        }
        if let action = plugins?.actionDefinition(id) {
            return action.command
        }
        return customActions.first(where: { $0.id == id })?.command
    }

    /// Resolved shell command. nil for unknown ids or empty custom commands.
    func command(for id: QuickActionId) -> String? {
        if let builtin = BuiltinQuickAction.from(id: id) {
            if let override = builtinCommandOverrides[id]?
                .trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
                return override
            }
            return builtin.defaultCommand
        }
        if let pluginCommand = plugins?.command(forAction: id) {
            return pluginCommand
        }
        guard let custom = customActions.first(where: { $0.id == id }) else { return nil }
        let trimmed = custom.command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Localized display name. Builtins go through the L10n catalog under
    /// the supplied locale; customs render their user-entered name; fully
    /// unknown ids return the id itself.
    func displayName(for id: QuickActionId, locale: Locale) -> String {
        if let builtin = BuiltinQuickAction.from(id: id) {
            return String(localized: builtin.displayName.withLocale(locale))
        }
        if let action = plugins?.actionDefinition(id) {
            return action.title
        }
        if let custom = customActions.first(where: { $0.id == id }) {
            let trimmed = custom.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? id : trimmed
        }
        return id
    }

    /// Icon hint for the row. Customs fall back to a `.letter` chip.
    func iconSource(for id: QuickActionId) -> QuickActionIcon {
        if let builtin = BuiltinQuickAction.from(id: id) {
            return builtin.iconSource
        }
        if let action = plugins?.actionDefinition(id) {
            return action.icon
        }
        let name = customActions.first(where: { $0.id == id })?
            .name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let first = name.first.map { Character(String($0).uppercased()) } ?? "?"
        return .letter(first)
    }

    /// What the top bar should render — enabled + existing, in `orderedIds`.
    var displayList: [QuickActionId] {
        orderedIds.filter { id in
            let pluginReady = plugins?.actionDefinition(id) == nil
                || (plugins?.isActionLaunchable(id) ?? false)
            return enabledSet.contains(id)
                && exists(id)
                && pluginReady
        }
    }

    /// What the Settings list should render — all existing ids in order.
    var fullList: [QuickActionId] {
        orderedIds.filter { exists($0) }
    }

    // MARK: - Mutate

    /// Toggle visibility in the top bar. Idempotent. `orderedIds` is NOT
    /// touched so the row keeps its place.
    func setEnabled(_ id: QuickActionId, _ enabled: Bool) {
        let was = enabledSet.contains(id)
        if enabled { enabledSet.insert(id) } else { enabledSet.remove(id) }
        if was != enabled { saveEnabled() }
    }

    /// Override a builtin's command. No-op for non-builtin ids. Empty /
    /// whitespace input clears the override.
    func setBuiltinCommand(_ id: QuickActionId, _ command: String) {
        guard BuiltinQuickAction.from(id: id) != nil else { return }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            builtinCommandOverrides.removeValue(forKey: id)
            settings.set(Self.kBuiltinCmd(id), nil)
        } else {
            builtinCommandOverrides[id] = command
            settings.set(Self.kBuiltinCmd(id), command)
        }
    }

    /// Insert an empty custom action; caller follows up with name + command
    /// via `updateCustomAction`. The new id is appended to `orderedIds`.
    @discardableResult
    func addCustomAction() -> QuickActionId {
        let id = UUID().uuidString
        customActions.append(CustomQuickAction(id: id, name: "", command: ""))
        orderedIds.append(id)
        saveCustom()
        saveOrder()
        return id
    }

    func updateCustomAction(_ id: QuickActionId, name: String? = nil, command: String? = nil) {
        guard let idx = customActions.firstIndex(where: { $0.id == id }) else { return }
        if let name { customActions[idx].name = name }
        if let command { customActions[idx].command = command }
        saveCustom()
    }

    func removeCustomAction(_ id: QuickActionId) {
        let beforeEnabled = enabledSet
        let beforeOrder = orderedIds
        customActions.removeAll { $0.id == id }
        enabledSet.remove(id)
        orderedIds.removeAll { $0 == id }
        saveCustom()
        if enabledSet != beforeEnabled { saveEnabled() }
        if orderedIds != beforeOrder { saveOrder() }
    }

    /// Reorder within the displayList (only enabled items visible in the
    /// top bar). Maps the post-move display order back into `orderedIds`
    /// by walking it and overwriting the enabled positions; disabled rows
    /// between them keep their slot.
    func reorderDisplay(from source: IndexSet, to destination: Int) {
        var working = displayList
        working.move(fromOffsets: source, toOffset: destination)
        let beforeOrder = orderedIds
        var iter = working.makeIterator()
        for (idx, id) in orderedIds.enumerated()
        where enabledSet.contains(id) && exists(id) {
            if let next = iter.next() { orderedIds[idx] = next }
        }
        if orderedIds != beforeOrder { saveOrder() }
    }

    /// Reorder within the fullList (Settings drag). Same mapping, broader.
    func reorderFull(from source: IndexSet, to destination: Int) {
        var working = fullList
        working.move(fromOffsets: source, toOffset: destination)
        let beforeOrder = orderedIds
        var iter = working.makeIterator()
        for (idx, id) in orderedIds.enumerated() where exists(id) {
            if let next = iter.next() { orderedIds[idx] = next }
        }
        if orderedIds != beforeOrder { saveOrder() }
    }

    /// Re-read from the underlying settings (use when the config file was
    /// edited out-of-band).
    func reloadFromSettings() {
        orderedIds.removeAll()
        enabledSet.removeAll()
        builtinCommandOverrides.removeAll()
        customActions.removeAll()
        load()
    }

    // MARK: - Load / save

    private func load() {
        // 1. Custom actions first so order migration can validate ids.
        if let raw = settings.get(Self.kCustom),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([CustomQuickAction].self, from: data) {
            customActions = decoded
        }
        // 2. Enabled set (membership) and a legacy snapshot of its order.
        var legacyEnabledOrder: [QuickActionId] = []
        if let raw = settings.get(Self.kEnabled),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([QuickActionId].self, from: data) {
            legacyEnabledOrder = decoded
            enabledSet = Set(decoded)
        }
        // 3. orderedIds — load, or migrate from legacy snapshot.
        if let raw = settings.get(Self.kOrder),
           let data = raw.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([QuickActionId].self, from: data) {
            orderedIds = decoded
        } else {
            // First-launch / pre-feature migration: enabled in given order,
            // then unseen builtins, then unseen customs.
            var seen = Set<QuickActionId>()
            var result: [QuickActionId] = []
            for id in legacyEnabledOrder where !seen.contains(id) {
                result.append(id); seen.insert(id)
            }
            for b in BuiltinQuickAction.allCases where !seen.contains(b.id) {
                result.append(b.id); seen.insert(b.id)
            }
            if let plugins {
                for id in PluginCatalog.actionIds where !seen.contains(id) && plugins.actionDefinition(id) != nil {
                    result.append(id); seen.insert(id)
                }
            }
            for c in customActions where !seen.contains(c.id) {
                result.append(c.id); seen.insert(c.id)
            }
            // First launch leaves enabledSet empty. The Settings ▸ Quick
            // Actions section is the user's
            // discovery path; first-launch enablement happens via an
            // explicit hook in `AppDelegate.applicationDidFinishLaunching`
            // so test stores can assert the empty default.
            orderedIds = result
        }
        // 4. Append late-arriving ids the saved order didn't have (new
        //    builtin shipped, custom slipped through). Preserves existing
        //    order for known ids.
        var seen = Set(orderedIds)
        for b in BuiltinQuickAction.allCases where !seen.contains(b.id) {
            orderedIds.append(b.id); seen.insert(b.id)
        }
        if let plugins {
            for id in PluginCatalog.actionIds where !seen.contains(id) && plugins.actionDefinition(id) != nil {
                orderedIds.append(id); seen.insert(id)
            }
        }
        for c in customActions where !seen.contains(c.id) {
            orderedIds.append(c.id); seen.insert(c.id)
        }
        // 5. Built-in command overrides.
        for b in BuiltinQuickAction.allCases {
            if let raw = settings.get(Self.kBuiltinCmd(b.id)),
               !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                builtinCommandOverrides[b.id] = raw
            }
        }
        saveOrder()   // idempotent: writes only when content differs
        saveEnabled() // ensure first-launch enabled set persists
    }

    private func saveEnabled() {
        let arr = orderedIds.filter { enabledSet.contains($0) }
        if let data = try? JSONEncoder().encode(arr),
           let s = String(data: data, encoding: .utf8) {
            settings.set(Self.kEnabled, s)
        }
    }

    private func saveCustom() {
        if let data = try? JSONEncoder().encode(customActions),
           let s = String(data: data, encoding: .utf8) {
            settings.set(Self.kCustom, s)
        }
    }

    private func saveOrder() {
        if let data = try? JSONEncoder().encode(orderedIds),
           let s = String(data: data, encoding: .utf8) {
            settings.set(Self.kOrder, s)
        }
    }
}
