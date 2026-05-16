import SwiftUI

/// Settings > Shell — shell integration, default command, and the in0
/// git-tab helper command.
struct ShellSectionView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.locale) private var locale

    private static let managedKeys = [
        "shell-integration",
        "shell-integration-features",
        "command",
        "in0-git-viewer",
    ]

    var body: some View {
        let theme = themeManager.currentTheme
        Form {
            BoundSegmented(
                settings: configStore,
                key: "shell-integration",
                options: ["detect", "none", "fish", "zsh", "bash"],
                label: L10n.Settings.Shell.integration
            )

            BoundMultiSelect(
                settings: configStore,
                key: "shell-integration-features",
                allOptions: ["cursor", "sudo", "title", "ssh-env"],
                label: L10n.Settings.Shell.features
            )

            BoundTextField(
                settings: configStore,
                theme: theme,
                key: "command",
                placeholder: L10n.Settings.shellPlaceholder,
                label: L10n.Settings.shellCommand
            )

            LabeledContent {
                TextField(String(localized: L10n.Settings.Shell.gitViewerPlaceholder.withLocale(locale)), text: Binding(
                    get: { settings.gitViewerCommand },
                    set: { settings.setGitViewerCommand($0) }
                ))
                .themedTextField(theme)
                .frame(width: 420)
            } label: {
                Text(L10n.Settings.Shell.gitViewer)
            }

            SettingsResetRow(settings: configStore, keys: Self.managedKeys)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
