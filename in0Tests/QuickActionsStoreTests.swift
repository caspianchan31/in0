import XCTest
@testable import in0

@MainActor
final class QuickActionsStoreTests: XCTestCase {

    private var tmpPaths: [String] = []

    override func tearDown() async throws {
        for p in tmpPaths { try? FileManager.default.removeItem(atPath: p) }
        tmpPaths.removeAll()
        try await super.tearDown()
    }

    private func makeSettings() -> SettingsConfigStore {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("in0-quickactions-\(UUID().uuidString).conf")
        tmpPaths.append(path)
        return SettingsConfigStore(filePath: path)
    }

    private func makeStore() -> (QuickActionsStore, SettingsConfigStore) {
        let settings = makeSettings()
        return (QuickActionsStore(settings: settings), settings)
    }

    // MARK: - Defaults

    func testFreshStoreIsEmpty() {
        let (store, _) = makeStore()
        XCTAssertTrue(store.enabledIds.isEmpty)
        XCTAssertTrue(store.builtinCommandOverrides.isEmpty)
        XCTAssertTrue(store.customActions.isEmpty)
        XCTAssertTrue(store.displayList.isEmpty)
    }

    // MARK: - Enable / disable

    func testSetEnabledAddsAndPersists() {
        let (store, settings) = makeStore()
        store.setEnabled("gitui", true)
        XCTAssertEqual(store.enabledIds, ["gitui"])
        settings.save()

        let store2 = QuickActionsStore(settings: settings)
        XCTAssertEqual(store2.enabledIds, ["gitui"])
    }

    func testSetEnabledIsIdempotent() {
        let (store, _) = makeStore()
        store.setEnabled("gitui", true)
        store.setEnabled("gitui", true)
        XCTAssertEqual(store.enabledIds, ["gitui"])
    }

    func testSetEnabledFalseRemoves() {
        let (store, _) = makeStore()
        store.setEnabled("gitui", true)
        store.setEnabled("claude", true)
        store.setEnabled("gitui", false)
        XCTAssertEqual(store.enabledIds, ["claude"])
    }

    // MARK: - Commands

    func testBuiltinDefaults() {
        let (store, _) = makeStore()
        XCTAssertEqual(store.command(for: "gitui"), "gitui")
        XCTAssertEqual(store.command(for: "claude"), "claude")
    }

    func testBuiltinCommandOverride() {
        let (store, _) = makeStore()
        store.setBuiltinCommand("gitui", "lazygit")
        XCTAssertEqual(store.command(for: "gitui"), "lazygit")
    }

    func testBuiltinEmptyOverrideClears() {
        let (store, _) = makeStore()
        store.setBuiltinCommand("gitui", "lazygit")
        store.setBuiltinCommand("gitui", "")
        XCTAssertEqual(store.command(for: "gitui"), "gitui")
        XCTAssertNil(store.builtinCommandOverrides["gitui"])
    }

    func testCommandForUnknownIdIsNil() {
        let (store, _) = makeStore()
        XCTAssertNil(store.command(for: "no-such-id"))
    }

    // MARK: - Custom

    func testAddCustomActionAppendsEmpty() {
        let (store, _) = makeStore()
        let id = store.addCustomAction()
        XCTAssertEqual(store.customActions.count, 1)
        XCTAssertEqual(store.customActions.first?.id, id)
        XCTAssertEqual(store.customActions.first?.name, "")
        XCTAssertEqual(store.customActions.first?.command, "")
        XCTAssertFalse(store.isEnabled(id))
    }

    func testUpdateCustomChangesNameAndCommand() {
        let (store, _) = makeStore()
        let id = store.addCustomAction()
        store.updateCustomAction(id, name: "htop", command: "htop -H")
        XCTAssertEqual(store.customActions.first?.name, "htop")
        XCTAssertEqual(store.customActions.first?.command, "htop -H")
        XCTAssertEqual(store.command(for: id), "htop -H")
    }

    func testRemoveCustomUnenables() {
        let (store, _) = makeStore()
        let id = store.addCustomAction()
        store.updateCustomAction(id, name: "htop", command: "htop")
        store.setEnabled(id, true)
        store.removeCustomAction(id)
        XCTAssertTrue(store.customActions.isEmpty)
        XCTAssertFalse(store.isEnabled(id))
    }

    // MARK: - Orphans

    func testDisplayListFiltersOrphanCustomIds() {
        let (_, settings) = makeStore()
        let orphan = "orphan-uuid"
        let json = try! JSONEncoder().encode([orphan])
        settings.set("in0-quickactions-enabled", String(data: json, encoding: .utf8))
        let store2 = QuickActionsStore(settings: settings)
        XCTAssertTrue(store2.enabledIds.isEmpty)
        XCTAssertTrue(store2.displayList.isEmpty)
    }

    func testFullListDropsOrphans() {
        let (_, settings) = makeStore()
        let json = try! JSONEncoder().encode(["orphan-uuid"])
        settings.set("in0-quickactions-enabled", String(data: json, encoding: .utf8))
        let store = QuickActionsStore(settings: settings)
        XCTAssertFalse(store.fullList.contains("orphan-uuid"))
    }

    // MARK: - Icons

    func testCustomIconIsLetter() {
        let (store, _) = makeStore()
        let id = store.addCustomAction()
        store.updateCustomAction(id, name: "htop")
        guard case .letter(let c) = store.iconSource(for: id) else {
            XCTFail("expected .letter"); return
        }
        XCTAssertEqual(c, "H")
    }

    func testEmptyCustomNameFallsBackToQuestionMark() {
        let (store, _) = makeStore()
        let id = store.addCustomAction()
        guard case .letter(let c) = store.iconSource(for: id) else {
            XCTFail("expected .letter"); return
        }
        XCTAssertEqual(c, "?")
    }

    func testSetBuiltinCommandIgnoresNonBuiltin() {
        let (store, settings) = makeStore()
        store.setBuiltinCommand("not-a-builtin", "some-cmd")
        XCTAssertTrue(store.builtinCommandOverrides.isEmpty)
        XCTAssertNil(settings.get("in0-quickactions-builtin-command-not-a-builtin"))
    }

    // MARK: - Reorder

    func testReorderDisplayMovesEnabledIds() {
        let (store, _) = makeStore()
        store.setEnabled("gitui", true)
        store.setEnabled("claude", true)
        store.setEnabled("codex", true)
        let codexIdx = store.displayList.firstIndex(of: "codex")!
        store.reorderDisplay(from: IndexSet([codexIdx]), to: 0)
        XCTAssertEqual(store.displayList.first, "codex")
    }

    func testFullListStableAcrossEnableToggles() {
        let (store, _) = makeStore()
        let c1 = store.addCustomAction()
        let c2 = store.addCustomAction()
        let baseline = store.fullList
        XCTAssertEqual(baseline, BuiltinQuickAction.allCases.map(\.id) + [c1, c2])

        store.setEnabled("codex", true)
        store.setEnabled(c2, true)
        XCTAssertEqual(store.fullList, baseline)

        store.setEnabled("codex", false)
        XCTAssertEqual(store.fullList, baseline)
    }

    func testReorderFullMovesEnabledBuiltin() {
        let (store, _) = makeStore()
        store.setEnabled("gitui", true)
        store.setEnabled("claude", true)
        store.setEnabled("codex", true)
        let idx = store.fullList.firstIndex(of: "codex")!
        store.reorderFull(from: IndexSet([idx]), to: 0)
        XCTAssertEqual(store.enabledIds, ["codex", "gitui", "claude"])
        XCTAssertEqual(store.displayList, ["codex", "gitui", "claude"])
    }

    func testReorderFullDisabledItemPreservesEnabled() {
        let (store, _) = makeStore()
        store.setEnabled("gitui", true)
        let before = store.enabledIds
        let codexIdx = store.fullList.firstIndex(of: "codex")!
        store.reorderFull(from: IndexSet([codexIdx]), to: 0)
        XCTAssertEqual(store.enabledIds, before)
    }

    func testReorderFullMovingCustomChangesFullList() {
        let (store, _) = makeStore()
        let c1 = store.addCustomAction()
        let c2 = store.addCustomAction()
        let c3 = store.addCustomAction()
        let c3Idx = store.fullList.firstIndex(of: c3)!
        let gituiIdx = store.fullList.firstIndex(of: "gitui")!
        store.reorderFull(from: IndexSet([c3Idx]), to: gituiIdx + 1)
        let customs = store.fullList.filter { id in store.customActions.contains { $0.id == id } }
        XCTAssertEqual(customs, [c3, c1, c2])
    }

    // MARK: - Persistence

    func testOrderRoundTrips() {
        let (store, settings) = makeStore()
        let codexIdx = store.fullList.firstIndex(of: "codex")!
        store.reorderFull(from: IndexSet([codexIdx]), to: 0)
        let snap = store.fullList
        settings.save()

        let reload = QuickActionsStore(settings: settings)
        XCTAssertEqual(reload.fullList, snap)
    }

    func testLegacyEnabledOnlyMigrates() {
        let settings = makeSettings()
        let json = try! JSONEncoder().encode(["codex", "gitui"])
        settings.set("in0-quickactions-enabled", String(data: json, encoding: .utf8))

        let store = QuickActionsStore(settings: settings)
        XCTAssertEqual(store.fullList, ["codex", "gitui", "claude", "opencode"])

        store.setEnabled("codex", false)
        XCTAssertEqual(store.fullList, ["codex", "gitui", "claude", "opencode"])
    }
}
