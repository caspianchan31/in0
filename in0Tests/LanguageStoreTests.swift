import XCTest
@testable import in0

@MainActor
final class LanguageStoreTests: XCTestCase {
    private let testKey = "in0.language.test"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testDefaultChoiceIsSystem() {
        XCTAssertEqual(LanguageStore(storageKey: testKey).choice, .system)
    }

    func testChoicePersists() {
        let a = LanguageStore(storageKey: testKey)
        a.choice = .zh
        let b = LanguageStore(storageKey: testKey)
        XCTAssertEqual(b.choice, .zh)
    }

    func testInvalidStoredFallsBackToSystem() {
        UserDefaults.standard.set("bogus", forKey: testKey)
        XCTAssertEqual(LanguageStore(storageKey: testKey).choice, .system)
    }

    func testTickIncrementsOnChange() {
        let store = LanguageStore(storageKey: testKey)
        let before = store.tick
        store.choice = .zh
        XCTAssertEqual(store.tick, before &+ 1)
    }

    func testTickIdleOnSameValue() {
        let store = LanguageStore(storageKey: testKey)
        store.choice = .zh
        let mid = store.tick
        store.choice = .zh
        XCTAssertEqual(store.tick, mid)
    }

    func testLocaleForZh() {
        let store = LanguageStore(storageKey: testKey)
        store.choice = .zh
        XCTAssertEqual(store.locale.identifier, "zh-Hans")
    }

    func testLocaleForEn() {
        let store = LanguageStore(storageKey: testKey)
        store.choice = .en
        XCTAssertEqual(store.locale.identifier, "en")
    }

    func testLocaleForSystemMatchesCurrent() {
        let store = LanguageStore(storageKey: testKey)
        store.choice = .system
        XCTAssertEqual(store.locale, .current)
    }

    func testEffectiveBundleForZhFindsLproj() {
        let store = LanguageStore(storageKey: testKey)
        store.choice = .zh
        XCTAssertTrue(store.effectiveBundle.bundlePath.contains("zh-Hans.lproj"),
                      "bundlePath = \(store.effectiveBundle.bundlePath)")
    }

    func testEffectiveBundleForEnFindsLproj() {
        let store = LanguageStore(storageKey: testKey)
        store.choice = .en
        XCTAssertTrue(store.effectiveBundle.bundlePath.contains("en.lproj"),
                      "bundlePath = \(store.effectiveBundle.bundlePath)")
    }
}
