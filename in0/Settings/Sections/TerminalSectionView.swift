import SwiftUI

/// Settings > Terminal — ghostty behavior keys that can be hot-reloaded or
/// applied to newly-created surfaces through the shared in0 override config.
struct TerminalSectionView: View {
    @Environment(SettingsConfigStore.self) private var configStore

    private static let managedKeys = [
        "scrollback-limit",
        "copy-on-select",
        "mouse-hide-while-typing",
        "confirm-close-surface",
    ]

    var body: some View {
        Form {
            BoundStepper(
                settings: configStore,
                key: "scrollback-limit",
                defaultValue: 10_000_000,
                range: 0...100_000_000,
                label: L10n.Settings.Terminal.scrollbackLimit
            )

            BoundSegmented(
                settings: configStore,
                key: "copy-on-select",
                options: ["false", "true", "clipboard"],
                label: L10n.Settings.Terminal.copyOnSelect
            )

            BoundToggle(
                settings: configStore,
                key: "mouse-hide-while-typing",
                defaultValue: false,
                label: L10n.Settings.Terminal.hideMouseWhileTyping
            )

            BoundSegmented(
                settings: configStore,
                key: "confirm-close-surface",
                options: ["true", "false", "always"],
                label: L10n.Settings.Terminal.confirmClose
            )

            SettingsResetRow(settings: configStore, keys: Self.managedKeys)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
