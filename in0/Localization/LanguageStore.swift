import Foundation
import Observation

/// Picks the active UI language. `system` follows the macOS preferred
/// locale; `en` and `zh` force the corresponding xcstrings bundle.
///
/// A `.shared` singleton exists so AppKit code (which can't read SwiftUI's
/// `\.locale` environment) can resolve strings through `L10n.string(_:)`.
@MainActor
@Observable
final class LanguageStore {
    enum Choice: String, Codable, CaseIterable {
        case system, en, zh
    }

    static let shared = LanguageStore()

    static let defaultStorageKey = "in0.language.v1"

    private let storageKey: String
    private let defaults: UserDefaults

    var choice: Choice {
        didSet {
            guard oldValue != choice else { return }
            defaults.set(choice.rawValue, forKey: storageKey)
            tick &+= 1
        }
    }

    /// Increments on every change. Views that read AppKit-resolved strings
    /// (no `\.locale` plumbing) can observe this to force a redraw.
    private(set) var tick: UInt = 0

    init(storageKey: String = LanguageStore.defaultStorageKey,
         defaults: UserDefaults = .standard) {
        self.storageKey = storageKey
        self.defaults = defaults
        if let raw = defaults.string(forKey: storageKey),
           let c = Choice(rawValue: raw) {
            self.choice = c
        } else {
            self.choice = .system
        }
    }

    /// The Locale to feed into Text/Date formatting / String(localized:withLocale:).
    var locale: Locale {
        switch choice {
        case .system: return .current
        case .en: return Locale(identifier: "en")
        case .zh: return Locale(identifier: "zh-Hans")
        }
    }

    /// The Bundle whose `Localizable.xcstrings` should be consulted for AppKit
    /// strings. Returns the main bundle for `.system` (so macOS picks the
    /// user's preferred language); otherwise drills into the explicit lproj.
    var effectiveBundle: Bundle {
        switch choice {
        case .system: return .main
        case .en: return Self.bundle(for: "en") ?? .main
        case .zh: return Self.bundle(for: "zh-Hans") ?? .main
        }
    }

    private static func bundle(for code: String) -> Bundle? {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let b = Bundle(path: path) else { return nil }
        return b
    }
}
