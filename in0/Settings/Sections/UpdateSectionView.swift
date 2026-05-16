import SwiftUI

/// Settings > Update — grouped rows for the Sparkle state machine.
struct UpdateSectionView: View {
    @Environment(UpdateStore.self) private var updateStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.locale) private var locale

    var body: some View {
        let theme = themeManager.currentTheme
        Form {
            LabeledContent(String(localized: L10n.Settings.Update.currentVersion.withLocale(locale))) {
                Text(updateStore.currentVersion)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
            }

            LabeledContent(String(localized: L10n.Settings.Update.status.withLocale(locale))) {
                statusContent(theme: theme)
            }

            if showsActionRow {
                LabeledContent(String(localized: L10n.Settings.Update.action.withLocale(locale))) {
                    actionContent
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var showsActionRow: Bool {
        guard SparkleBridge.shared.isActive else { return false }
        switch updateStore.state {
        case .idle, .upToDate, .updateAvailable, .error:
            return true
        case .checking, .downloading, .readyToInstall:
            return false
        }
    }

    @ViewBuilder
    private func statusContent(theme: AppTheme) -> some View {
        switch updateStore.state {
        case .idle:
            if SparkleBridge.shared.isActive {
                Text(L10n.Settings.Update.upToDate)
                    .foregroundStyle(theme.textSecondary)
            } else {
                Text(L10n.Settings.Update.unavailable)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
                    .multilineTextAlignment(.trailing)
            }
        case .checking:
            HStack(spacing: DT.Space.sm) {
                ProgressView().controlSize(.small)
                Text(L10n.Settings.Update.checking)
                    .foregroundStyle(theme.textSecondary)
            }
        case .upToDate:
            Label(String(localized: L10n.Settings.Update.upToDate.withLocale(locale)), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .updateAvailable(let version, let notes):
            VStack(alignment: .trailing, spacing: DT.Space.xs) {
                Text("v\(version)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                if let notes, !notes.isEmpty {
                    Text(notes)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(4)
                }
            }
        case .downloading(let progress):
            HStack(spacing: DT.Space.sm) {
                ProgressView(value: progress)
                    .frame(minWidth: 120)
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
                    .frame(width: DT.Space.xl * 2, alignment: .trailing)
            }
        case .readyToInstall:
            HStack(spacing: DT.Space.sm) {
                ProgressView().controlSize(.small)
                Text(L10n.Settings.Update.installing)
                    .foregroundStyle(theme.textPrimary)
            }
        case .error(let message):
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(theme.danger)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var actionContent: some View {
        switch updateStore.state {
        case .idle, .upToDate:
            Button(String(localized: L10n.Settings.Update.checkForUpdates.withLocale(locale))) {
                SparkleBridge.shared.checkForUpdates(silently: false)
            }
        case .updateAvailable:
            ViewThatFits(in: .horizontal) {
                HStack(spacing: DT.Space.sm) {
                    updateAvailableButtons
                }
                VStack(alignment: .trailing, spacing: DT.Space.xs) {
                    updateAvailableButtons
                }
            }
        case .error:
            Button(String(localized: L10n.Settings.Update.retry.withLocale(locale))) {
                SparkleBridge.shared.retry()
            }
        case .checking, .downloading, .readyToInstall:
            EmptyView()
        }
    }

    @ViewBuilder
    private var updateAvailableButtons: some View {
        Button(String(localized: L10n.Settings.Update.downloadInstall.withLocale(locale))) {
            SparkleBridge.shared.downloadAndInstall()
        }
        .buttonStyle(.borderedProminent)
        Button(String(localized: L10n.Settings.Update.skipThisVersion.withLocale(locale))) {
            SparkleBridge.shared.skipVersion()
        }
        Button(String(localized: L10n.Settings.Update.dismiss.withLocale(locale))) {
            SparkleBridge.shared.dismiss()
        }
    }
}
