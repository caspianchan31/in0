import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

/// The single touchpoint to Sparkle. Mirrors how `GhosttyBridge` isolates
/// libghostty: keep the dependency import to ONE file, expose a small Swift
/// API the rest of the app talks to.
///
/// When Sparkle isn't linked (Debug, CI, fresh clones), this compiles as a
/// no-op stub: `isActive` returns false, action methods log and return.
/// That way the rest of the app — menu items, Settings UI, sidebar dot —
/// keeps working without a valid `SUPublicEDKey` / `SUFeedURL`.
@MainActor
final class SparkleBridge {
    static let shared = SparkleBridge()

    /// Set by `in0App` once `UpdateStore` exists. The user driver mutates
    /// the store directly; the bridge holds it weakly for the few action
    /// paths (skip / dismiss / retry) that need to consult or reset state.
    weak var store: UpdateStore?

    var isActive: Bool {
        #if canImport(Sparkle)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Public API

    func start() {
        #if canImport(Sparkle)
        startUpdater()
        #endif
    }

    func checkForUpdates(silently: Bool) {
        #if canImport(Sparkle)
        if silently {
            updater?.checkForUpdatesInBackground()
        } else {
            updater?.checkForUpdates()
        }
        #else
        NSLog("[SparkleBridge] stub: checkForUpdates(silently: \(silently)) — link Sparkle to enable")
        #endif
    }

    func downloadAndInstall() {
        #if canImport(Sparkle)
        driver?.userRequestedDownloadAndInstall()
        #else
        NSLog("[SparkleBridge] stub: downloadAndInstall")
        #endif
    }

    func skipVersion() {
        #if canImport(Sparkle)
        driver?.userRequestedSkipVersion()
        #else
        NSLog("[SparkleBridge] stub: skipVersion")
        #endif
    }

    func dismiss() {
        #if canImport(Sparkle)
        driver?.userRequestedDismiss()
        store?.resetToIdle()
        #else
        store?.resetToIdle()
        #endif
    }

    func retry() {
        #if canImport(Sparkle)
        store?.resetToIdle()
        // If startUpdater failed earlier (missing feed URL / public key),
        // updater stays nil and a plain checkForUpdates would silently
        // no-op. Re-attempt start() so retry can recover.
        if updater == nil { startUpdater() }
        checkForUpdates(silently: false)
        #else
        store?.resetToIdle()
        #endif
    }

    // MARK: - Sparkle internals

    #if canImport(Sparkle)
    private var updater: SPUUpdater?
    private var driver: UpdateUserDriver?

    private func startUpdater() {
        guard updater == nil else { return }
        guard let store = store else {
            NSLog("[SparkleBridge] start called before store was injected")
            return
        }
        let driver = UpdateUserDriver(store: store)
        let upd = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: driver,
            delegate: nil
        )
        do {
            try upd.start()
        } catch {
            store.setError("Updater failed to start: \(error.localizedDescription)")
            return
        }
        self.updater = upd
        self.driver = driver
    }
    #endif
}
