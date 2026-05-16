import AppKit

/// Lives inside a TabContentView. Owns one GhosttyTerminalView per terminal
/// id; views are kept in memory across tab switches so the running shell and
/// scrollback survive.
@MainActor
final class SurfaceCache {
    private var views: [UUID: GhosttyTerminalView] = [:]

    func view(for terminalId: UUID) -> GhosttyTerminalView {
        if let v = views[terminalId] { return v }
        let v = GhosttyTerminalView(terminalId: terminalId)
        views[terminalId] = v
        return v
    }

    /// Free surfaces for ids that no longer appear in `aliveIds`. Called
    /// after the workspace store mutates the layout.
    func reapMissing(aliveIds: Set<UUID>) {
        let dead = views.keys.filter { !aliveIds.contains($0) }
        for id in dead {
            views[id]?.dispose()
            views.removeValue(forKey: id)
        }
    }

    func disposeAll() {
        for v in views.values { v.dispose() }
        views.removeAll()
    }
}
