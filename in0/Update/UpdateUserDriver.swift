import Foundation
#if canImport(Sparkle)
import Sparkle

/// Sparkle's `SPUUserDriver` implementation. Translates Sparkle events into
/// `UpdateStore` state transitions; conversely, stores reply blocks so the
/// app's UI buttons can resume the flow (download / skip / install /
/// dismiss). All callbacks pin to the main actor — Sparkle invokes them on
/// the main queue, but the protocol isn't declared `MainActor`-isolated.
@MainActor
final class UpdateUserDriver: NSObject, SPUUserDriver {

    private let store: UpdateStore
    /// Sparkle hands these reply blocks to the driver when asking the user
    /// to choose. We retain them and call the chosen reply when the user
    /// hits one of our buttons (Download / Skip / Install Later).
    private var updateChoiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var installUpdateReply: ((SPUUserUpdateChoice) -> Void)?

    init(store: UpdateStore) {
        self.store = store
        super.init()
    }

    // MARK: - SPUUserDriver

    func showUpdateInProgress(_ checking: Bool) {
        Task { @MainActor in store.setChecking() }
    }

    func showUpdateCheckInitiated(completion: @escaping () -> Void) {
        Task { @MainActor in store.setChecking() }
        completion()
    }

    func showUpdateFoundWithAppcastItem(
        _ appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        self.updateChoiceReply = reply
        Task { @MainActor [weak self] in
            self?.store.setUpdateAvailable(
                version: appcastItem.displayVersionString,
                notes: appcastItem.itemDescription
            )
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { /* using description body */ }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { /* description still shown */ }

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            self?.store.setUpToDate()
            // Auto-clear after a few seconds — matches user expectation that
            // "Up to date" is a transient confirmation, not a sticky state.
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if self?.store.state == .upToDate {
                self?.store.resetToIdle()
            }
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        Task { @MainActor [weak self] in
            self?.store.setError(error.localizedDescription)
        }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        Task { @MainActor [weak self] in self?.store.setDownloading(progress: 0) }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        // Without expected length info, treat each chunk as nudging progress
        // forward — better feedback than a frozen 0%. The actual progress
        // signal comes through Sparkle's percent reporter when available.
        Task { @MainActor [weak self] in
            guard let self else { return }
            if case .downloading(let p) = self.store.state {
                self.store.setDownloading(progress: min(p + 0.02, 0.95))
            }
        }
    }

    func showDownloadDidStartExtractingUpdate() { }

    func showExtractionReceivedProgress(_ progress: Double) {
        Task { @MainActor [weak self] in self?.store.setDownloading(progress: progress) }
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        self.installUpdateReply = reply
        Task { @MainActor [weak self] in self?.store.setReadyToInstall() }
    }

    func showInstallingUpdate(withApplicationTerminationHandler applicationTerminated: @escaping () -> Void) {
        applicationTerminated()
    }

    func showSendingTerminationSignal() { }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() { }

    func dismissUpdateInstallation() { }

    // MARK: - User-side actions (forwarded by SparkleBridge)

    func userRequestedDownloadAndInstall() {
        if let reply = updateChoiceReply {
            updateChoiceReply = nil
            reply(.install)
            return
        }
        if let reply = installUpdateReply {
            installUpdateReply = nil
            reply(.install)
        }
    }

    func userRequestedSkipVersion() {
        if let reply = updateChoiceReply {
            updateChoiceReply = nil
            reply(.skip)
        }
        store.resetToIdle()
    }

    func userRequestedDismiss() {
        if let reply = updateChoiceReply {
            updateChoiceReply = nil
            reply(.dismiss)
        }
        if let reply = installUpdateReply {
            installUpdateReply = nil
            reply(.dismiss)
        }
    }
}
#endif
