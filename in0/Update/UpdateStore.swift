import Foundation
import Observation

/// Single source of truth for the auto-update flow. Lives in the SwiftUI
/// environment; consumed by sidebar (red dot) and Settings ▸ Update.
///
/// All mutations happen here. Sparkle integration (`UpdateUserDriver`)
/// calls these helpers; views never mutate `state` directly. Keeping the
/// state machine isolated to one type means the UI can render arbitrary
/// combinations during development without re-pluming Sparkle through.
@MainActor
@Observable
final class UpdateStore {
    /// Current app version (`CFBundleShortVersionString`). Read once.
    let currentVersion: String

    /// Active UI state.
    var state: UpdateState = .idle

    /// True while an update is somewhere in the pipeline. Sidebar polls
    /// this to decide whether to show the pulsing dot. `.readyToInstall`
    /// is kept lit so the dot doesn't flicker off during the few-ms
    /// handoff to Sparkle relaunch.
    var hasUpdate: Bool {
        switch state {
        case .updateAvailable, .downloading, .readyToInstall: return true
        default: return false
        }
    }

    init(currentVersion: String? = nil) {
        if let v = currentVersion {
            self.currentVersion = v
        } else if let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            self.currentVersion = bundleVersion
        } else {
            self.currentVersion = "0.0.0"
        }
    }

    func setChecking()                                         { state = .checking }
    func setUpToDate()                                         { state = .upToDate }
    func setUpdateAvailable(version: String, notes: String?)   { state = .updateAvailable(version: version, releaseNotes: notes) }
    func setDownloading(progress: Double)                      { state = .downloading(progress: progress) }
    func setReadyToInstall()                                   { state = .readyToInstall }
    func setError(_ message: String)                           { state = .error(message) }
    func resetToIdle()                                         { state = .idle }
}
