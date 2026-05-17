import SwiftUI

/// Settings > Appearance. Every control occupies a single labeled row,
/// with scrolling owned by Form instead of an outer freeform ScrollView.
struct AppearanceSectionView: View {
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(LanguageStore.self) private var languageStore

    private static let managedKeys = [
        "theme",
        "follows-terminal-background",
        "status-indicators-enabled",
        "background-opacity",
        "background-blur-radius",
        "in0-content-opacity",
        "in0-content-shadow",
        "window-padding-x",
        "window-padding-y",
        "cursor-style",
        "cursor-style-blink",
        "unfocused-split-opacity",
    ]

    var body: some View {
        Form {
            ThemePickerView(settings: configStore, theme: themeManager.currentTheme)

            BoundToggle(
                settings: configStore,
                key: "follows-terminal-background",
                defaultValue: true,
                label: L10n.Settings.followsTerminalBg
            )

            BoundToggle(
                settings: configStore,
                key: "status-indicators-enabled",
                defaultValue: true,
                label: L10n.Settings.statusIndicators
            )

            BoundSlider(
                settings: configStore,
                key: "background-opacity",
                defaultValue: 1.0,
                range: 0.0...1.0,
                step: 0.05,
                label: L10n.Settings.backgroundOpacity
            )

            BoundSlider(
                settings: configStore,
                key: "background-blur-radius",
                defaultValue: 0,
                range: 0...100,
                step: 1,
                label: L10n.Settings.backgroundBlur
            )

            BoundSlider(
                settings: configStore,
                key: "in0-content-opacity",
                defaultValue: 1.0,
                range: 0.0...1.0,
                step: 0.05,
                label: L10n.Settings.contentOpacity
            )

            BoundSlider(
                settings: configStore,
                key: "in0-content-shadow",
                defaultValue: 0,
                range: 0.0...1.0,
                step: 0.05,
                label: L10n.Settings.contentShadow
            )

            BoundStepper(
                settings: configStore,
                key: "window-padding-x",
                defaultValue: 4,
                range: 0...100,
                label: L10n.Settings.windowPaddingX
            )

            BoundStepper(
                settings: configStore,
                key: "window-padding-y",
                defaultValue: 4,
                range: 0...100,
                label: L10n.Settings.windowPaddingY
            )

            BoundSegmented(
                settings: configStore,
                key: "cursor-style",
                options: ["block", "bar", "underline"],
                label: L10n.Settings.cursorStyle
            )

            BoundToggle(
                settings: configStore,
                key: "cursor-style-blink",
                defaultValue: false,
                label: L10n.Settings.cursorBlink
            )

            BoundSlider(
                settings: configStore,
                key: "unfocused-split-opacity",
                defaultValue: 0.7,
                range: 0.0...1.0,
                step: 0.05,
                label: L10n.Settings.unfocusedPaneOpacity
            )

            LabeledContent {
                Picker("", selection: Binding(
                    get: { languageStore.choice },
                    set: { languageStore.choice = $0 }
                )) {
                    Text(L10n.Settings.languageSystem).tag(LanguageStore.Choice.system)
                    Text(verbatim: "English").tag(LanguageStore.Choice.en)
                    Text(verbatim: "中文（简体）").tag(LanguageStore.Choice.zh)
                    Text(verbatim: "中文（繁體）").tag(LanguageStore.Choice.zhHant)
                    Text(verbatim: "日本語").tag(LanguageStore.Choice.ja)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            } label: {
                Text(L10n.Settings.language)
            }

            SettingsResetRow(settings: configStore, keys: Self.managedKeys)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
