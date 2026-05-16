import SwiftUI

/// Settings panel section for managing Quick Actions. Lists every known
/// action (built-in + custom) in `orderedIds` order, lets the user enable
/// / disable / rename / re-command / reorder / delete via QuickActionRow.
struct QuickActionsSectionView: View {
    @Environment(QuickActionsStore.self) private var store
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(ThemeManager.self) private var themeManager
    @Environment(\.locale) private var locale

    private static let managedKeys: [String] = {
        var keys = [
            "in0-quickactions-enabled",
            "in0-quickactions-custom",
            "in0-quickactions-order",
        ]
        keys.append(contentsOf: BuiltinQuickAction.allCases.map {
            "in0-quickactions-builtin-command-\($0.id)"
        })
        return keys
    }()

    var body: some View {
        let theme = themeManager.currentTheme
        Form {
            Section {
                List {
                    ForEach(store.fullList, id: \.self) { id in
                        QuickActionRowView(
                            id: id,
                            store: store,
                            theme: theme,
                            isBuiltin: BuiltinQuickAction.from(id: id) != nil
                        )
                    }
                    .onMove { source, destination in
                        store.reorderFull(from: source, to: destination)
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 240, maxHeight: 360)
                .scrollContentBackground(.hidden)
            } header: {
                Text(L10n.Settings.QuickActions.heading)
            } footer: {
                Text(L10n.Settings.QuickActions.headingFooter)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }

            Section {
                Button {
                    store.addCustomAction()
                } label: {
                    Label(
                        String(localized: L10n.Settings.QuickActions.addCustomButton.withLocale(locale)),
                        systemImage: "plus.circle"
                    )
                }
                .buttonStyle(.borderless)
            }

            SettingsResetRow(
                settings: configStore,
                keys: Self.managedKeys,
                additionalAction: { store.reloadFromSettings() }
            )
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}
