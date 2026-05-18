import AppKit
import SwiftUI

/// SwiftUI wrapper around the AppKit `TabContentView`. Drives the AppKit
/// view from the workspace store and forwards user actions back.
struct TabBridge: NSViewRepresentable {
    @Environment(WorkspaceStore.self) private var store
    @Environment(ThemeManager.self) private var themeManager
    @Environment(QuickActionsStore.self) private var quickActions
    @Environment(LanguageStore.self) private var language

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> TabContentView {
        let view = TabContentView(theme: themeManager.currentTheme)
        view.onAddTab = { [weak store] in
            guard let store, let wsId = store.selectedId else { return }
            store.addTab(to: wsId)
        }
        view.onSplitVertical = { [weak store] in
            guard let store, let wsId = store.selectedId else { return }
            store.splitFocused(in: wsId, direction: .vertical)
        }
        view.onSplitHorizontal = { [weak store] in
            guard let store, let wsId = store.selectedId else { return }
            store.splitFocused(in: wsId, direction: .horizontal)
        }
        view.onSelectTab = { [weak store] id in
            guard let store, let wsId = store.selectedId else { return }
            store.selectTab(id, in: wsId)
        }
        view.onCloseTab = { [weak store] id in
            guard let store, let wsId = store.selectedId else { return }
            store.closeTab(id, in: wsId)
        }
        view.onCloseOtherTabs = { [weak store] id in
            guard let store, let wsId = store.selectedId else { return }
            store.closeOtherTabs(keeping: id, in: wsId)
        }
        view.onCloseTabsToRight = { [weak store] id in
            guard let store, let wsId = store.selectedId else { return }
            store.closeTabsToRight(of: id, in: wsId)
        }
        view.onRatioChange = { [weak store] tabId, splitId, ratio in
            guard let store, let wsId = store.selectedId else { return }
            store.updateRatio(splitId, to: ratio, in: wsId, tabId: tabId)
        }
        view.onFocusTerminal = { [weak store] tabId, termId in
            guard let store, let wsId = store.selectedId else { return }
            store.setFocusedTerminal(termId, in: wsId, tabId: tabId)
        }
        view.onRenameTab = { [weak store] tabId, newTitle in
            guard let store, let wsId = store.selectedId else { return }
            store.renameTab(tabId, in: wsId, to: newTitle)
        }
        view.onReorderTabs = { [weak store] from, to in
            guard let store, let wsId = store.selectedId else { return }
            store.moveTab(in: wsId, from: from, to: to)
        }
        view.onQuickAction = { [weak store, weak quickActions] id in
            guard let store, let quickActions else { return }
            let title = quickActions.displayName(for: id, locale: .current)
            store.launchInNewTab(title: title, quickActionId: id)
        }
        view.onTabDropOnPane = { [weak store] droppedTabId, ontoTabId, ontoTermId, edge in
            guard let store, let wsId = store.selectedId else { return }
            store.dropTabIntoPane(
                in: wsId,
                droppedTabId: droppedTabId,
                targetTabId: ontoTabId,
                targetTerminalId: ontoTermId,
                edge: edge
            )
        }
        if let ws = store.selectedWorkspace {
            view.apply(workspace: ws, liveTerminalIds: store.liveTerminalIds)
        }
        view.applyQuickActions(currentDescriptors())
        return view
    }

    func updateNSView(_ nsView: TabContentView, context: Context) {
        nsView.theme = themeManager.currentTheme
        if let ws = store.selectedWorkspace {
            nsView.apply(workspace: ws, liveTerminalIds: store.liveTerminalIds)
        } else {
            nsView.clearWorkspace()
        }
        nsView.applyQuickActions(currentDescriptors())
    }

    /// Map the store's display list into the AppKit view's lightweight
    /// descriptor shape. The view is intentionally decoupled from
    /// QuickActionsStore so it doesn't re-observe through every change —
    /// SwiftUI triggers the update path when an observed property fires.
    private func currentDescriptors() -> [QuickActionDescriptor] {
        let locale = language.locale
        return quickActions.displayList.map { id -> QuickActionDescriptor in
            let title = quickActions.displayName(for: id, locale: locale)
            let cmd = quickActions.command(for: id) ?? ""
            let icon = quickActions.iconSource(for: id)
            switch icon {
            case .sfSymbol(let name):
                return QuickActionDescriptor(
                    id: id, title: title, tooltip: "Launch \(cmd)",
                    symbolName: name, assetName: nil, letter: nil
                )
            case .letter(let c):
                return QuickActionDescriptor(
                    id: id, title: title, tooltip: "Launch \(cmd)",
                    symbolName: nil, assetName: nil, letter: c
                )
            case .asset(let name):
                let first = title.first.map { Character(String($0).uppercased()) } ?? "?"
                return QuickActionDescriptor(
                    id: id, title: title, tooltip: "Launch \(cmd)",
                    symbolName: nil, assetName: name, letter: first
                )
            }
        }
    }

    final class Coordinator {}
}

private extension WorkspaceStore {
    var liveTerminalIds: Set<UUID> {
        Set(workspaces.flatMap { workspace in
            workspace.tabs.flatMap { $0.layout.allTerminalIds() }
        })
    }
}
