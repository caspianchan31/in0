import SwiftUI

struct PluginsSectionView: View {
    @Environment(PluginStore.self) private var plugins
    @Environment(QuickActionsStore.self) private var quickActions
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(ThemeManager.self) private var themeManager

    private static let managedKeys = ["in0-plugins-enabled", PluginStore.kVisibleCards]

    var body: some View {
        let theme = themeManager.currentTheme
        Form {
            Section {
                List {
                    ForEach(plugins.definitions) { plugin in
                        PluginRowView(
                            plugin: plugin,
                            plugins: plugins,
                            quickActions: quickActions,
                            theme: theme
                        )
                    }
                }
                .listStyle(.plain)
                .frame(minHeight: 220, maxHeight: 360)
                .scrollContentBackground(.hidden)
            } header: {
                Text("Plugins")
            } footer: {
                Text("Plugins add workspace cards beside the terminal. Quick Actions remain optional.")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }

            SettingsResetRow(
                settings: configStore,
                keys: Self.managedKeys,
                additionalAction: {
                    plugins.reset()
                    quickActions.reloadFromSettings()
                }
            )
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

private struct PluginRowView: View {
    let plugin: PluginDefinition
    let plugins: PluginStore
    let quickActions: QuickActionsStore
    let theme: AppTheme

    var body: some View {
        HStack(alignment: .top, spacing: DT.Space.sm) {
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 22, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: DT.Space.xs) {
                    Text(plugin.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(plugin.kind.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: DT.Radius.sm, style: .continuous)
                                .stroke(theme.border.opacity(0.75), lineWidth: DT.Stroke.hairline)
                        )
                    Spacer(minLength: DT.Space.sm)
                }

                Text(plugin.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)

                if let action = plugin.quickActions.first {
                    Toggle("Show in Quick Actions", isOn: quickActionBinding(action.id))
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)
                        .disabled(!plugins.isEnabled(plugin.id))
                        .foregroundStyle(theme.textSecondary)
                }

                if let card = plugin.cards.first {
                    Toggle("Show in Card Sidebar", isOn: cardBinding(card.id))
                        .font(.system(size: 11))
                        .toggleStyle(.checkbox)
                        .disabled(!plugins.isEnabled(plugin.id))
                        .foregroundStyle(theme.textSecondary)
                }
            }

            Toggle("", isOn: pluginBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel("Enable \(plugin.title)")
        }
        .padding(.vertical, 6)
    }

    private var iconName: String {
        switch plugin.kind {
        case .task: return "checklist"
        case .scanner: return "dot.viewfinder"
        }
    }

    private var pluginBinding: Binding<Bool> {
        Binding(
            get: { plugins.isEnabled(plugin.id) },
            set: { enabled in
                plugins.setEnabled(plugin.id, enabled)
                if !enabled {
                    for action in plugin.quickActions {
                        quickActions.setEnabled(action.id, false)
                    }
                    for card in plugin.cards {
                        plugins.setCardVisible(card.id, false)
                    }
                }
            }
        )
    }

    private func quickActionBinding(_ id: QuickActionId) -> Binding<Bool> {
        Binding(
            get: { quickActions.isEnabled(id) },
            set: { quickActions.setEnabled(id, $0) }
        )
    }

    private func cardBinding(_ id: PluginCardId) -> Binding<Bool> {
        Binding(
            get: { plugins.isCardVisible(id) },
            set: { plugins.setCardVisible(id, $0) }
        )
    }
}
