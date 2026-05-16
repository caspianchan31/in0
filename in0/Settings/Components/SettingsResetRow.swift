import SwiftUI

/// Trailing row in each Settings section. Left column: a "Restore
/// Defaults" label; right column: a Reset button that, on confirm, wipes
/// every config key owned by the section. Removing the keys from the in0
/// config file lets ghostty fall back to its own defaults; the 200 ms
/// debounce in `SettingsConfigStore` coalesces N deletes into one disk
/// hit + one reload-config flash.
struct SettingsResetRow: View {
    let settings: SettingsConfigStore
    let keys: [String]
    /// Sections that own state outside `SettingsConfigStore` (Agents'
    /// `ResumeStore`, QuickActions' UserDefaults dustbin, etc.) pass a
    /// closure here so the reset clears everything atomically instead of
    /// leaving related state stale.
    var additionalAction: () -> Void = { }

    @State private var confirming = false
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent(String(localized: L10n.Settings.resetRowLabel.withLocale(locale))) {
            Button {
                confirming = true
            } label: {
                Text(L10n.Settings.resetButton)
            }
            .buttonStyle(.bordered)
        }
        .alert(
            String(localized: L10n.Settings.resetAlertTitle.withLocale(locale)),
            isPresented: $confirming
        ) {
            Button(String(localized: L10n.Settings.resetButton.withLocale(locale)), role: .destructive) {
                for key in keys { settings.set(key, nil) }
                additionalAction()
            }
            Button(String(localized: L10n.Settings.resetCancel.withLocale(locale)), role: .cancel) { }
        } message: {
            Text(L10n.Settings.resetMessage)
        }
    }
}
