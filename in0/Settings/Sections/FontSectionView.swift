import SwiftUI

/// Settings > Font — terminal font family + size, rendered as compact
/// grouped rows.
struct FontSectionView: View {
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(ThemeManager.self) private var themeManager

    private static let managedKeys = [
        "font-family",
        "font-size",
        "font-thicken",
    ]

    var body: some View {
        Form {
            FontPickerView(
                settings: configStore,
                theme: themeManager.currentTheme,
                label: L10n.Settings.fontFamily
            )

            BoundStepper(
                settings: configStore,
                key: "font-size",
                defaultValue: 13,
                range: 8...32,
                label: L10n.Settings.fontSize
            )

            BoundToggle(
                settings: configStore,
                key: "font-thicken",
                defaultValue: false,
                label: L10n.Settings.fontThicken
            )

            SettingsResetRow(settings: configStore, keys: Self.managedKeys)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
