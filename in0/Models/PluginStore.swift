import Foundation
import Observation

@MainActor
@Observable
final class PluginStore {
    private(set) var enabledIds: Set<PluginId> = []
    private(set) var visibleCardIds: Set<PluginCardId> = []

    private let settings: SettingsConfigStore
    private static let kEnabled = "in0-plugins-enabled"
    static let kVisibleCards = "in0-plugin-cards-visible"

    init(settings: SettingsConfigStore) {
        self.settings = settings
        load()
    }

    var definitions: [PluginDefinition] { PluginCatalog.definitions }

    func isEnabled(_ id: PluginId) -> Bool {
        enabledIds.contains(id)
    }

    func supports(_ surface: PluginSurface, pluginId: PluginId) -> Bool {
        PluginCatalog.definition(id: pluginId)?.surfaces.contains(surface) ?? false
    }

    func isCardVisible(_ id: PluginCardId) -> Bool {
        visibleCardIds.contains(id)
    }

    var visibleWorkspaceCards: [PluginCardSurface] {
        PluginCatalog.definitions.reduce(into: [PluginCardSurface]()) { out, plugin in
            guard isEnabled(plugin.id) else { return }
            out.append(contentsOf: plugin.cards.filter { visibleCardIds.contains($0.id) })
        }
    }

    func setEnabled(_ id: PluginId, _ enabled: Bool) {
        guard PluginCatalog.definition(id: id) != nil else { return }
        let before = enabledIds
        let beforeCards = visibleCardIds
        if enabled {
            enabledIds.insert(id)
            if let plugin = PluginCatalog.definition(id: id) {
                for card in plugin.cards where plugin.surfaces.contains(.workspaceCard) {
                    visibleCardIds.insert(card.id)
                }
            }
        } else {
            enabledIds.remove(id)
            if let plugin = PluginCatalog.definition(id: id) {
                for card in plugin.cards {
                    visibleCardIds.remove(card.id)
                }
            }
        }
        if enabledIds != before { saveEnabled() }
        if visibleCardIds != beforeCards { saveVisibleCards() }
    }

    func setCardVisible(_ id: PluginCardId, _ visible: Bool) {
        guard let pair = PluginCatalog.card(id: id),
              pair.plugin.surfaces.contains(.workspaceCard) else { return }
        let before = visibleCardIds
        if visible {
            visibleCardIds.insert(id)
        } else {
            visibleCardIds.remove(id)
        }
        if before != visibleCardIds { saveVisibleCards() }
    }

    func pluginForAction(_ actionId: QuickActionId) -> PluginDefinition? {
        PluginCatalog.action(id: actionId)?.plugin
    }

    func actionDefinition(_ actionId: QuickActionId) -> PluginQuickAction? {
        PluginCatalog.action(id: actionId)?.action
    }

    func isActionLaunchable(_ actionId: QuickActionId) -> Bool {
        guard let plugin = pluginForAction(actionId) else { return false }
        return isEnabled(plugin.id)
    }

    func command(forAction actionId: QuickActionId) -> String? {
        guard isActionLaunchable(actionId),
              let action = actionDefinition(actionId) else { return nil }
        let trimmed = action.command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func reloadFromSettings() {
        enabledIds.removeAll()
        visibleCardIds.removeAll()
        load()
    }

    func reset() {
        enabledIds.removeAll()
        visibleCardIds.removeAll()
        settings.set(Self.kEnabled, nil)
        settings.set(Self.kVisibleCards, nil)
    }

    private func load() {
        guard let raw = settings.get(Self.kEnabled),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([PluginId].self, from: data) else {
            return
        }
        enabledIds = Set(decoded.filter { PluginCatalog.definition(id: $0) != nil })

        guard let rawCards = settings.get(Self.kVisibleCards),
              let cardData = rawCards.data(using: .utf8),
              let decodedCards = try? JSONDecoder().decode([PluginCardId].self, from: cardData) else {
            visibleCardIds = defaultVisibleCards(for: enabledIds)
            if !visibleCardIds.isEmpty { saveVisibleCards() }
            return
        }
        visibleCardIds = Set(decodedCards.filter { PluginCatalog.card(id: $0) != nil })
    }

    private func defaultVisibleCards(for enabledIds: Set<PluginId>) -> Set<PluginCardId> {
        Set(
            PluginCatalog.definitions
                .filter { enabledIds.contains($0.id) && $0.surfaces.contains(.workspaceCard) }
                .flatMap { $0.cards.map(\.id) }
        )
    }

    private func saveEnabled() {
        let ordered = PluginCatalog.definitions.map(\.id).filter { enabledIds.contains($0) }
        if let data = try? JSONEncoder().encode(ordered),
           let s = String(data: data, encoding: .utf8) {
            settings.set(Self.kEnabled, s)
        }
    }

    private func saveVisibleCards() {
        let ordered = PluginCatalog.cardIds.filter { visibleCardIds.contains($0) }
        if ordered.isEmpty {
            settings.set(Self.kVisibleCards, nil)
            return
        }
        if let data = try? JSONEncoder().encode(ordered),
           let s = String(data: data, encoding: .utf8) {
            settings.set(Self.kVisibleCards, s)
        }
    }
}
