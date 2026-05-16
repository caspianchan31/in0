import SwiftUI
import XCTest
@testable import in0

/// Drives `SidebarListBridge` end-to-end: spawns NSHostingView, lets
/// SwiftUI build the AppKit `WorkspaceListView` underneath, then walks
/// the subview tree to count `WorkspaceRowItemView`s. The row class is
/// `private` to its file, so we identify it by class name string rather
/// than `as?` (which wouldn't compile).
@MainActor
final class SidebarListBridgeTests: XCTestCase {

    // MARK: - Test rig

    private func makeStore(workspaceCount: Int) -> WorkspaceStore {
        let key = "in0.test.sidebar.\(UUID().uuidString)"
        // seedDefault: false so we can assert exact counts including 0.
        let store = WorkspaceStore(persistenceKey: key, seedDefault: false)
        for i in 0..<workspaceCount {
            store.addWorkspace(name: "ws\(i)")
        }
        return store
    }

    private func materialize(
        _ store: WorkspaceStore,
        metadata: [UUID: WorkspaceMetadataSnapshot] = [:],
        tick: Int = 0
    ) throws -> (NSHostingView<AnyView>, WorkspaceListView) {
        // Build the dependencies the bridge expects. ThemeManager / etc.
        // live in the SwiftUI environment of NSHostingView; provide them
        // directly via .environment(...).
        let themeManager = ThemeManager()
        let language = LanguageStore(storageKey: "in0.test.lang.\(UUID())")
        let bridge = SidebarListBridge(
            store: store,
            statusStore: TerminalStatusStore(),
            theme: themeManager.currentTheme,
            metadata: metadata,
            metadataTick: tick,
            languageTick: language.tick,
            onRequestDelete: { _ in },
            onRequestEditCommand: { _, _ in }
        )
        let host = NSHostingView(rootView: AnyView(
            bridge
                .environment(themeManager)
                .environment(language)
        ))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 400)
        host.layout()
        // Let SwiftUI flush its initial pass.
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let listView = try XCTUnwrap(
            findFirst(WorkspaceListView.self, in: host),
            "WorkspaceListView not found in hosting view tree"
        )
        return (host, listView)
    }

    private func findFirst<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let hit = view as? T { return hit }
        for sub in view.subviews {
            if let hit = findFirst(type, in: sub) { return hit }
        }
        return nil
    }

    /// Walk all subviews and count rows by class-name match (the row
    /// class is fileprivate, so we can't `as?` it from outside).
    private func rowCount(in listView: WorkspaceListView) -> Int {
        var n = 0
        var queue: [NSView] = [listView]
        while let v = queue.first {
            queue.removeFirst()
            if String(describing: type(of: v)).contains("WorkspaceRowItemView") {
                n += 1
            }
            queue.append(contentsOf: v.subviews)
        }
        return n
    }

    // MARK: - Tests

    func testProducesListViewWithCorrectRowCount() throws {
        let store = makeStore(workspaceCount: 2)
        let (_, listView) = try materialize(store)
        XCTAssertEqual(rowCount(in: listView), 2)
    }

    func testEmptyStoreYieldsZeroRows() throws {
        let store = makeStore(workspaceCount: 0)
        let (_, listView) = try materialize(store)
        XCTAssertEqual(rowCount(in: listView), 0)
    }

    func testRowCountReflectsStoreMutations() throws {
        let store = makeStore(workspaceCount: 1)
        let (host, listView) = try materialize(store)
        XCTAssertEqual(rowCount(in: listView), 1)

        store.addWorkspace(name: "second")
        host.layout()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(rowCount(in: listView), 2)

        if let first = store.workspaces.first {
            store.removeWorkspace(first.id)
        }
        host.layout()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(rowCount(in: listView), 1)
    }
}
