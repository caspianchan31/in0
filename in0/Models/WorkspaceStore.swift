import Foundation
import Observation

/// Single source of truth for workspaces, tabs, and split layout.
/// Persists to UserDefaults. Surfaces are not part of the persisted state.
@MainActor
@Observable
final class WorkspaceStore {
    static let defaultStorageKey = "in0.workspaces.v1"
    static let defaultSelectedKey = "in0.workspaces.v1.selected"

    private let storageKey: String
    private let selectedKey: String
    private let seedDefaultWorkspace: Bool

    private(set) var workspaces: [Workspace]
    var selectedId: UUID?

    /// Resolver hook installed by `AppDelegate.attach`. Whenever the store
    /// creates a new terminal (via `addTab`, `splitFocused`, or
    /// `launchInNewTab`), this callback is invoked with the new terminal
    /// id, its owning tab, and the owning workspace. The returned command
    /// (if non-nil) is enqueued for the surface to drain on first viewing.
    ///
    /// Decoupled this way so `WorkspaceStore` doesn't have to depend on
    /// `QuickActionsStore` / `SettingsStore` / `ResumeStore` directly; the
    /// host wires the resolver in one place and the store stays portable.
    var startupCommandPolicy: ((_ terminalId: UUID, _ tab: TerminalTab, _ workspace: Workspace) -> String?)?

    /// Inheritance hook used by `addTab` / `splitFocused` so a freshly
    /// spawned terminal starts in the same pwd as the pane the user
    /// branched from. Installed by `AppDelegate.attach` and backed by
    /// `TerminalPwdStore.inherit(from:to:)`.
    var inheritPwdPolicy: ((_ source: UUID, _ destination: UUID) -> Void)?
    var terminalCleanup: ((_ terminalId: UUID) -> Void)?

    /// Production init reads/writes the standard `in0.workspaces.v1` key
    /// and seeds a `default` workspace on first launch.
    convenience init() {
        self.init(persistenceKey: WorkspaceStore.defaultStorageKey, seedDefault: true)
    }

    /// Test/multi-instance init lets the caller pin a unique persistence
    /// key (so parallel tests don't trample each other's UserDefaults)
    /// and skip the auto-`default` seed (so an empty store stays empty).
    init(persistenceKey: String, seedDefault: Bool = false) {
        self.storageKey = persistenceKey
        self.selectedKey = persistenceKey + ".selected"
        self.seedDefaultWorkspace = seedDefault
        let decoded = Self.loadWorkspaces(key: persistenceKey)
        if decoded.isEmpty && seedDefault {
            let initial = Workspace(name: "default", tabs: [TerminalTab(title: "shell")])
            self.workspaces = [initial]
            self.selectedId = initial.id
            save()
        } else {
            self.workspaces = decoded
            self.selectedId = Self.loadSelectedId(key: self.selectedKey) ?? decoded.first?.id
        }
    }

    var selectedWorkspace: Workspace? {
        guard let selectedId else { return nil }
        return workspaces.first { $0.id == selectedId }
    }

    func indexOfWorkspace(_ id: UUID) -> Int? {
        workspaces.firstIndex { $0.id == id }
    }

    // MARK: - Workspace CRUD

    func select(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        selectedId = id
        save()
    }

    @discardableResult
    func addWorkspace(name: String) -> Workspace {
        let ws = Workspace(name: name, tabs: [TerminalTab(title: "shell")])
        workspaces.append(ws)
        selectedId = ws.id
        save()
        return ws
    }

    func removeWorkspace(_ id: UUID) {
        if let ws = workspaces.first(where: { $0.id == id }) {
            cleanup(terminalsIn: ws)
        }
        workspaces.removeAll { $0.id == id }
        if selectedId == id { selectedId = workspaces.first?.id }
        save()
    }

    func renameWorkspace(_ id: UUID, to newName: String) {
        guard let idx = indexOfWorkspace(id) else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        workspaces[idx].name = trimmed
        save()
    }

    /// Update a workspace's default shell command — the fallback the
    /// `StartupCommandResolver` falls through to when no Quick Action or
    /// agent resume is queued. Empty / whitespace clears the override.
    func updateDefaultCommand(_ id: UUID, command: String?) {
        guard let idx = indexOfWorkspace(id) else { return }
        let trimmed = command?.trimmingCharacters(in: .whitespacesAndNewlines)
        workspaces[idx].defaultCommand = (trimmed?.isEmpty == true) ? nil : trimmed
        save()
    }

    func moveWorkspace(from source: Int, to destination: Int) {
        guard source >= 0, source < workspaces.count else { return }
        var dst = max(0, min(destination, workspaces.count))
        if dst > source { dst -= 1 }
        let item = workspaces.remove(at: source)
        workspaces.insert(item, at: min(dst, workspaces.count))
        save()
    }

    /// IndexSet overload — matches SwiftUI's `.onMove` and the
    /// SidebarListBridge wire format. The single-index source case maps
    /// directly to the Int form above.
    func moveWorkspace(from source: IndexSet, to destination: Int) {
        guard let first = source.first else { return }
        moveWorkspace(from: first, to: destination)
    }

    // MARK: - Tab CRUD

    @discardableResult
    func addTab(to workspaceId: UUID, title: String = "shell", quickActionId: QuickActionId? = nil) -> TerminalTab? {
        guard let wi = indexOfWorkspace(workspaceId) else { return nil }
        // Capture the previously-focused terminal id BEFORE we mutate the
        // selection. That's the pane whose pwd we want the new tab's first
        // terminal to inherit (`cd` continuity matches user intuition).
        let inheritSource: UUID? = workspaces[wi].selectedTabId
            .flatMap { id in workspaces[wi].tabs.first(where: { $0.id == id }) }
            .map(\.focusedTerminalId)

        let tab = TerminalTab(title: title, quickActionId: quickActionId)
        workspaces[wi].tabs.append(tab)
        workspaces[wi].selectedTabId = tab.id

        if let leafId = tab.layout.allTerminalIds().first {
            if let src = inheritSource {
                inheritPwdPolicy?(src, leafId)
            }
            if let cmd = startupCommandPolicy?(leafId, tab, workspaces[wi]) {
                TerminalCommandQueue.shared.enqueue(cmd, for: leafId)
            }
        }
        save()
        return tab
    }

    func selectTab(_ tabId: UUID, in workspaceId: UUID) {
        guard let wi = indexOfWorkspace(workspaceId),
              workspaces[wi].tabs.contains(where: { $0.id == tabId }) else { return }
        workspaces[wi].selectedTabId = tabId
        save()
    }

    func closeTab(_ tabId: UUID, in workspaceId: UUID) {
        guard let wi = indexOfWorkspace(workspaceId) else { return }
        if let tab = workspaces[wi].tabs.first(where: { $0.id == tabId }) {
            cleanup(terminalsIn: tab)
        }
        workspaces[wi].tabs.removeAll { $0.id == tabId }
        if workspaces[wi].selectedTabId == tabId {
            workspaces[wi].selectedTabId = workspaces[wi].tabs.first?.id
        }
        // never let a workspace become empty — recreate one shell tab
        if workspaces[wi].tabs.isEmpty {
            let tab = TerminalTab(title: "shell")
            workspaces[wi].tabs.append(tab)
            workspaces[wi].selectedTabId = tab.id
        }
        save()
    }

    func renameTab(_ tabId: UUID, in workspaceId: UUID, to newTitle: String) {
        guard let wi = indexOfWorkspace(workspaceId),
              let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        workspaces[wi].tabs[ti].title = newTitle
        save()
    }

    func moveTab(in workspaceId: UUID, from source: Int, to destination: Int) {
        guard let wi = indexOfWorkspace(workspaceId),
              source >= 0, source < workspaces[wi].tabs.count else { return }
        var dst = max(0, min(destination, workspaces[wi].tabs.count))
        if dst > source { dst -= 1 }
        let item = workspaces[wi].tabs.remove(at: source)
        workspaces[wi].tabs.insert(item, at: min(dst, workspaces[wi].tabs.count))
        save()
    }

    // MARK: - Split CRUD

    /// Split the focused leaf of the focused tab. Returns the new terminal id.
    @discardableResult
    func splitFocused(in workspaceId: UUID, direction: SplitDirection) -> UUID? {
        guard let wi = indexOfWorkspace(workspaceId),
              let tabId = workspaces[wi].selectedTabId,
              let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == tabId }) else { return nil }
        let focusedId = workspaces[wi].tabs[ti].focusedTerminalId
        let newId = UUID()
        let newSubtree = SplitNode.split(
            id: UUID(),
            direction: direction,
            firstRatio: 0.5,
            first: .terminal(focusedId),
            second: .terminal(newId)
        )
        workspaces[wi].tabs[ti].layout = workspaces[wi].tabs[ti].layout
            .replacing(terminalId: focusedId, with: newSubtree)
        workspaces[wi].tabs[ti].focusedTerminalId = newId
        // Split inheritance: the new pane starts in the same pwd as the
        // pane we just split off of.
        inheritPwdPolicy?(focusedId, newId)
        if let policy = startupCommandPolicy {
            let tab = workspaces[wi].tabs[ti]
            if let cmd = policy(newId, tab, workspaces[wi]) {
                TerminalCommandQueue.shared.enqueue(cmd, for: newId)
            }
        }
        save()
        return newId
    }

    func updateRatio(_ splitId: UUID, to newRatio: Double, in workspaceId: UUID, tabId: UUID) {
        guard let wi = indexOfWorkspace(workspaceId),
              let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        workspaces[wi].tabs[ti].layout = workspaces[wi].tabs[ti].layout
            .updatingRatio(splitId: splitId, to: newRatio)
        save() // ratio writes are debounced by the view layer (drag end)
    }

    func closeTerminal(_ terminalId: UUID, in workspaceId: UUID, tabId: UUID) {
        guard let wi = indexOfWorkspace(workspaceId),
              let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let newLayout = workspaces[wi].tabs[ti].layout.removing(terminalId: terminalId)
        if let newLayout {
            terminalCleanup?(terminalId)
            workspaces[wi].tabs[ti].layout = newLayout
            if workspaces[wi].tabs[ti].focusedTerminalId == terminalId {
                workspaces[wi].tabs[ti].focusedTerminalId = newLayout.allTerminalIds().first ?? UUID()
            }
            save()
        } else {
            // last terminal in the tab — close the tab itself
            closeTab(tabId, in: workspaceId)
        }
    }

    func setFocusedTerminal(_ terminalId: UUID, in workspaceId: UUID, tabId: UUID) {
        guard let wi = indexOfWorkspace(workspaceId),
              let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        workspaces[wi].tabs[ti].focusedTerminalId = terminalId
        save()
    }

    /// Splice a dropped tab's layout into the target tab as a new split next
    /// to the target leaf. The dropped tab is removed afterwards. If dropped
    /// onto its own pane this is a no-op.
    func dropTabIntoPane(
        in workspaceId: UUID,
        droppedTabId: UUID,
        targetTabId: UUID,
        targetTerminalId: UUID,
        edge: NSRectEdge
    ) {
        guard let wi = indexOfWorkspace(workspaceId),
              droppedTabId != targetTabId,
              let srcIdx = workspaces[wi].tabs.firstIndex(where: { $0.id == droppedTabId }),
              let dstIdx = workspaces[wi].tabs.firstIndex(where: { $0.id == targetTabId })
        else { return }
        let droppedLayout = workspaces[wi].tabs[srcIdx].layout

        let direction: SplitDirection
        let droppedGoesFirst: Bool
        switch edge {
        case .minX: direction = .vertical;   droppedGoesFirst = true
        case .maxX: direction = .vertical;   droppedGoesFirst = false
        case .minY: direction = .horizontal; droppedGoesFirst = true
        case .maxY: direction = .horizontal; droppedGoesFirst = false
        @unknown default: direction = .vertical; droppedGoesFirst = false
        }
        let newSubtree: SplitNode = .split(
            id: UUID(),
            direction: direction,
            firstRatio: 0.5,
            first: droppedGoesFirst ? droppedLayout : .terminal(targetTerminalId),
            second: droppedGoesFirst ? .terminal(targetTerminalId) : droppedLayout
        )
        workspaces[wi].tabs[dstIdx].layout = workspaces[wi].tabs[dstIdx].layout
            .replacing(terminalId: targetTerminalId, with: newSubtree)
        // Remove the source tab — its surfaces are now grafted into the target.
        workspaces[wi].tabs.remove(at: srcIdx)
        if workspaces[wi].selectedTabId == droppedTabId {
            workspaces[wi].selectedTabId = targetTabId
        }
        save()
    }

    // MARK: - High-level actions (for keyboard / menu)

    /// Add a tab to the currently selected workspace.
    @discardableResult
    func addTabToSelected(title: String = "shell") -> TerminalTab? {
        guard let wsId = selectedId else { return nil }
        return addTab(to: wsId, title: title)
    }

    /// Add a tab launched from a Quick Action and mark it with the action's
    /// id so the StartupCommandResolver can pick it up at surface-creation
    /// time (and so a future "resume in this tab" gesture can identify the
    /// right agent). The actual command resolution happens through
    /// `startupCommandPolicy` inside `addTab`.
    func launchInNewTab(title: String, quickActionId: QuickActionId) {
        guard let wsId = selectedId else { return }
        _ = addTab(to: wsId, title: title, quickActionId: quickActionId)
    }

    /// Switch to (or create) the workspace's dedicated git tab. Single
    /// `.git` tab per workspace — repeat clicks just refocus it. The
    /// initial command (`gitui` / `lazygit` / etc.) is queued for the
    /// surface to drain on first viewing.
    @discardableResult
    func ensureGitTab(command: String) -> TerminalTab? {
        guard let wsId = selectedId,
              let wi = indexOfWorkspace(wsId) else { return nil }
        if let existing = workspaces[wi].tabs.first(where: { $0.kind == .git }) {
            workspaces[wi].selectedTabId = existing.id
            save()
            return existing
        }
        // Snapshot the previously-focused terminal so the new git tab
        // can inherit its pwd (so `gitui` opens on the right repo).
        let inheritSource: UUID? = workspaces[wi].selectedTabId
            .flatMap { id in workspaces[wi].tabs.first(where: { $0.id == id }) }
            .map(\.focusedTerminalId)

        let tab = TerminalTab(title: "git", kind: .git)
        workspaces[wi].tabs.append(tab)
        workspaces[wi].selectedTabId = tab.id
        if let leafId = tab.layout.allTerminalIds().first {
            if let src = inheritSource {
                inheritPwdPolicy?(src, leafId)
            }
            TerminalCommandQueue.shared.enqueue(command, for: leafId)
        }
        save()
        return tab
    }

    /// Close the currently selected tab in the selected workspace.
    func closeSelectedTab() {
        guard let wsId = selectedId,
              let wi = indexOfWorkspace(wsId),
              let tabId = workspaces[wi].selectedTabId else { return }
        closeTab(tabId, in: wsId)
    }

    /// Close the currently focused terminal pane. If the tab has only one
    /// pane, this collapses to closing the tab itself (matching the user's
    /// intuition for ⌘W). Maps to the app's "Close Pane" command.
    func closeFocusedPane() {
        guard let wsId = selectedId,
              let wi = indexOfWorkspace(wsId),
              let tabId = workspaces[wi].selectedTabId,
              let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let tab = workspaces[wi].tabs[ti]
        closeTerminal(tab.focusedTerminalId, in: wsId, tabId: tabId)
    }

    /// Split the focused pane of the current tab.
    func splitFocusedInSelected(direction: SplitDirection) {
        guard let wsId = selectedId else { return }
        splitFocused(in: wsId, direction: direction)
    }

    /// Select the next tab (wraps). No-op if zero or one tab.
    func selectNextTab() {
        cycleTab(by: 1)
    }

    /// Select the previous tab (wraps).
    func selectPrevTab() {
        cycleTab(by: -1)
    }

    /// Select the tab at `index` in the current workspace's tab list,
    /// 0-based. No-op when out of range.
    func selectTab(atIndex index: Int) {
        guard let wsId = selectedId,
              let wi = indexOfWorkspace(wsId),
              index >= 0, index < workspaces[wi].tabs.count else { return }
        let tab = workspaces[wi].tabs[index]
        selectTab(tab.id, in: wsId)
    }

    private func cycleTab(by offset: Int) {
        guard let wsId = selectedId,
              let wi = indexOfWorkspace(wsId),
              let current = workspaces[wi].selectedTabId,
              let ci = workspaces[wi].tabs.firstIndex(where: { $0.id == current }),
              workspaces[wi].tabs.count > 1 else { return }
        let count = workspaces[wi].tabs.count
        let next = (ci + offset + count) % count
        selectTab(workspaces[wi].tabs[next].id, in: wsId)
    }

    /// Move focus to the neighboring pane in the given direction (no-op at edges).
    func moveFocus(_ direction: FocusDirection) {
        guard let wsId = selectedId,
              let wi = indexOfWorkspace(wsId),
              let tabId = workspaces[wi].selectedTabId,
              let ti = workspaces[wi].tabs.firstIndex(where: { $0.id == tabId }) else { return }
        let tab = workspaces[wi].tabs[ti]
        guard let next = tab.layout.neighbor(of: tab.focusedTerminalId, direction: direction) else { return }
        workspaces[wi].tabs[ti].focusedTerminalId = next
        save()
    }

    // MARK: - Persistence

    private func save() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        if let selectedId {
            UserDefaults.standard.set(selectedId.uuidString, forKey: selectedKey)
        }
    }

    private static func loadWorkspaces(key: String) -> [Workspace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([Workspace].self, from: data)
        else { return [] }
        return decoded
    }

    private static func loadSelectedId(key: String) -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }

    private func cleanup(terminalsIn workspace: Workspace) {
        workspace.tabs.forEach(cleanup(terminalsIn:))
    }

    private func cleanup(terminalsIn tab: TerminalTab) {
        tab.layout.allTerminalIds().forEach { terminalCleanup?($0) }
    }
}
