import Foundation

/// Drives `UpdateSectionView` and the sidebar red-dot. Single source of
/// truth for the user-visible auto-update flow.
enum UpdateState: Equatable {
    /// Resting state. Settings shows current version + "Check for Updates".
    case idle
    /// Network request in flight.
    case checking
    /// Confirmed no update. Auto-transitions back to `.idle` after a short
    /// confirmation delay (3 s in the view).
    case upToDate
    /// Update found and ready to start downloading.
    /// - version: e.g. "0.2.0"
    /// - releaseNotes: appcast `<description>` body, plain text. May be nil.
    case updateAvailable(version: String, releaseNotes: String?)
    /// Download in progress; `progress` is a 0...1 fraction.
    case downloading(progress: Double)
    /// Brief window (typically a few ms) between download finishing and
    /// Sparkle relaunching the app.
    case readyToInstall
    /// Any failure. Settings UI renders a red card + Retry button.
    case error(String)
}
