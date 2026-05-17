import XCTest
@testable import in0

@MainActor
final class PluginStoreTests: XCTestCase {
    private var tmpPaths: [String] = []

    override func tearDown() async throws {
        for p in tmpPaths { try? FileManager.default.removeItem(atPath: p) }
        tmpPaths.removeAll()
        try await super.tearDown()
    }

    private func makeSettings() -> SettingsConfigStore {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("in0-plugins-\(UUID().uuidString).conf")
        tmpPaths.append(path)
        return SettingsConfigStore(filePath: path)
    }

    func testCatalogContainsInitialBuiltins() {
        let settings = makeSettings()
        let store = PluginStore(settings: settings)

        XCTAssertEqual(store.definitions.map(\.id), ["todo-list", "github-scan", "agent-status", "ai-history"])
        XCTAssertEqual(store.definitions.flatMap { $0.quickActions.map(\.id) }, [
            "plugin.todo-list.open",
            "plugin.github-scan.run",
            "plugin.ai-history.list",
        ])
    }

    func testEnablePersistsInCatalogOrder() {
        let settings = makeSettings()
        let store = PluginStore(settings: settings)

        store.setEnabled("github-scan", true)
        store.setEnabled("todo-list", true)
        settings.save()

        let reload = PluginStore(settings: settings)
        XCTAssertTrue(reload.isEnabled("todo-list"))
        XCTAssertTrue(reload.isEnabled("github-scan"))
        XCTAssertEqual(settings.get("in0-plugins-enabled"), "[\"todo-list\",\"github-scan\"]")
    }

    func testCatalogContainsWorkspaceCards() {
        let settings = makeSettings()
        let store = PluginStore(settings: settings)

        XCTAssertEqual(store.definitions.flatMap { $0.cards.map(\.id) }, [
            "todo",
            "github-scan",
            "agent-status",
            "ai-history",
        ])
        XCTAssertTrue(store.supports(.workspaceCard, pluginId: "todo-list"))
        XCTAssertTrue(store.supports(.cardDetail, pluginId: "github-scan"))
    }

    func testCardVisibilityRequiresEnabledPlugin() {
        let settings = makeSettings()
        let store = PluginStore(settings: settings)

        store.setCardVisible("todo", true)
        XCTAssertTrue(store.visibleWorkspaceCards.isEmpty)

        store.setEnabled("todo-list", true)
        XCTAssertEqual(store.visibleWorkspaceCards.map(\.id), ["todo"])

        store.setCardVisible("todo", false)
        XCTAssertTrue(store.visibleWorkspaceCards.isEmpty)
    }

    func testCardVisibilityPersistsInCatalogOrderAndFiltersUnknowns() {
        let settings = makeSettings()
        settings.set("in0-plugins-enabled", "[\"agent-status\",\"todo-list\",\"ai-history\",\"unknown\"]")
        settings.set(PluginStore.kVisibleCards, "[\"agent-status\",\"todo\",\"ai-history\",\"unknown\"]")
        settings.save()

        let reload = PluginStore(settings: settings)

        XCTAssertTrue(reload.isEnabled("todo-list"))
        XCTAssertTrue(reload.isEnabled("agent-status"))
        XCTAssertTrue(reload.isEnabled("ai-history"))
        XCTAssertEqual(reload.visibleWorkspaceCards.map(\.id), ["todo", "agent-status", "ai-history"])
    }

    func testEnabledPluginsWithoutCardKeyDefaultToVisibleCards() {
        let settings = makeSettings()
        settings.set("in0-plugins-enabled", "[\"todo-list\",\"agent-status\"]")
        settings.save()

        let reload = PluginStore(settings: settings)

        XCTAssertEqual(reload.visibleWorkspaceCards.map(\.id), ["todo", "agent-status"])
        XCTAssertEqual(settings.get(PluginStore.kVisibleCards), "[\"todo\",\"agent-status\"]")
    }

    func testDisablePluginHidesItsCards() {
        let settings = makeSettings()
        let store = PluginStore(settings: settings)

        store.setEnabled("todo-list", true)
        XCTAssertEqual(store.visibleWorkspaceCards.map(\.id), ["todo"])

        store.setEnabled("todo-list", false)
        XCTAssertTrue(store.visibleWorkspaceCards.isEmpty)
        XCTAssertNil(settings.get(PluginStore.kVisibleCards))
    }

    func testUnknownPluginIsIgnored() {
        let settings = makeSettings()
        let store = PluginStore(settings: settings)

        store.setEnabled("not-real", true)
        XCTAssertFalse(store.isEnabled("not-real"))
        XCTAssertNil(settings.get("in0-plugins-enabled"))
    }

    func testActionCommandRequiresEnabledPlugin() {
        let settings = makeSettings()
        let store = PluginStore(settings: settings)

        XCTAssertNil(store.command(forAction: "plugin.todo-list.open"))
        store.setEnabled("todo-list", true)
        XCTAssertNotNil(store.command(forAction: "plugin.todo-list.open"))
    }
}
