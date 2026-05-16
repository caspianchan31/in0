import AppKit
import SwiftUI

/// Bridges `WorkspaceListView` (AppKit) into SwiftUI. Wires the store
/// callbacks on every `updateNSView` so a freshly-pushed selection /
/// rename / move always lands; reads metadata + status snapshots from
/// the SwiftUI environment.
///
/// Two "ticker" inputs exist so SwiftUI can force a re-render without
/// us having to observe every metadata field individually:
///   - `metadataTick` — bumped by `SidebarView` whenever the metadata
///     store fires its observation;
///   - `languageTick` — bumped when `LanguageStore.tick` changes so the
///     right-click menu (built fresh on each open) picks up locale
///     changes.
struct SidebarListBridge: NSViewRepresentable {
    @Bindable var store: WorkspaceStore
    @Bindable var statusStore: TerminalStatusStore
    var theme: AppTheme
    var metadata: [UUID: WorkspaceMetadataSnapshot]
    var metadataTick: Int
    var languageTick: UInt
    /// Mirror of ghostty's `background-opacity` (0…1). Applied to
    /// selected / hovered row fills inside the row view.
    var backgroundOpacity: CGFloat = 1.0
    /// When `false`, rows skip painting the per-workspace status icon and
    /// reclaim its layout slot for the title. Used by the in-progress
    /// beta indicator toggle.
    var showStatusIndicators: Bool = false
    var onRequestDelete: (UUID) -> Void
    /// The SwiftUI shell presents the edit-default-command alert (it has
    /// to — alerts can't live inside an NSViewRepresentable cleanly).
    /// AppKit just bubbles the request up with the workspace id + the
    /// current command so the shell can seed its TextField.
    var onRequestEditCommand: (UUID, String) -> Void

    func makeNSView(context: Context) -> WorkspaceListView {
        let view = WorkspaceListView()
        wire(view)
        push(into: view)
        return view
    }

    func updateNSView(_ view: WorkspaceListView, context: Context) {
        // Touch the tickers so SwiftUI observes them and reruns body when
        // they change — even though we don't read their values.
        _ = metadataTick
        _ = languageTick
        wire(view)
        push(into: view)
        view.refreshLocalizedStrings()
    }

    private func push(into view: WorkspaceListView) {
        view.update(
            workspaces: store.workspaces,
            selectedId: store.selectedId,
            metadata: metadata,
            statuses: statusStore.statuses,
            theme: theme,
            backgroundOpacity: backgroundOpacity,
            showStatusIndicators: showStatusIndicators
        )
    }

    private func wire(_ view: WorkspaceListView) {
        view.onSelect = { id in store.select(id) }
        view.onRename = { id, name in store.renameWorkspace(id, to: name) }
        view.onReorder = { from, to in store.moveWorkspace(from: IndexSet([from]), to: to) }
        view.onRequestDelete = { id in onRequestDelete(id) }
        view.onRequestEditCommand = { id, current in onRequestEditCommand(id, current) }
    }
}
