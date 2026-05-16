import SwiftUI

/// Settings ▸ Agents — per-agent toggles for Notifications and Resume on
/// Launch. Both keys are stored in the shared in0 config file via
/// `SettingsStore`, namespaced as `agent-<agent>-{notifications,resume}`.
struct AgentsSectionView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(ThemeManager.self) private var themeManager

    private static let managedKeys = HookAgent.allCases.flatMap {
        ["agent-\($0.rawValue)-notifications", "agent-\($0.rawValue)-resume"]
    }

    var body: some View {
        let theme = themeManager.currentTheme
        Form {
            Section {
                notificationRow(for: .claude, theme: theme)
                notificationRow(for: .opencode, theme: theme)
                notificationRow(for: .codex, theme: theme)
            } header: {
                Text(L10n.Settings.Agents.notificationsTitle)
            } footer: {
                Text(L10n.Settings.Agents.notificationsFooter)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }

            Section {
                resumeRow(for: .claude, theme: theme)
                resumeRow(for: .opencode, theme: theme)
                resumeRow(for: .codex, theme: theme)
            } header: {
                Text(L10n.Settings.Agents.resumeTitle)
            } footer: {
                Text(L10n.Settings.Agents.resumeFooter)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }

            SettingsResetRow(
                settings: configStore,
                keys: Self.managedKeys,
                additionalAction: {
                    for agent in HookAgent.allCases {
                        ResumeStore.shared.clearCommands(for: agent)
                    }
                }
            )
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private func notificationRow(for agent: HookAgent, theme: AppTheme) -> some View {
        LabeledContent {
            Toggle("", isOn: notificationBinding(for: agent))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("\(String(localized: label(for: agent))) notifications")
        } label: {
            HStack(spacing: DT.Space.sm) {
                Text(label(for: agent))
                if agent == .codex {
                    betaBadge(theme: theme)
                }
            }
        }
    }

    private func resumeRow(for agent: HookAgent, theme: AppTheme) -> some View {
        LabeledContent {
            Toggle("", isOn: resumeBinding(for: agent))
                .labelsHidden()
                .toggleStyle(.switch)
                .accessibilityLabel("\(String(localized: label(for: agent))) resume on launch")
        } label: {
            Text(label(for: agent))
        }
    }

    private func notificationBinding(for agent: HookAgent) -> Binding<Bool> {
        Binding(
            get: { settings.prefs(for: agent).notificationsEnabled },
            set: { settings.setNotifications($0, for: agent) }
        )
    }

    private func resumeBinding(for agent: HookAgent) -> Binding<Bool> {
        Binding(
            get: { settings.prefs(for: agent).resumeOnLaunch },
            set: { newValue in
                settings.setResumeOnLaunch(newValue, for: agent)
                if !newValue {
                    ResumeStore.shared.clearCommands(for: agent)
                }
            }
        )
    }

    private func label(for agent: HookAgent) -> LocalizedStringResource {
        switch agent {
        case .claude: return L10n.Settings.Agents.claude
        case .codex: return L10n.Settings.Agents.codex
        case .opencode: return L10n.Settings.Agents.opencode
        }
    }

    private func betaBadge(theme: AppTheme) -> some View {
        Text(L10n.Settings.Agents.betaBadge)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(theme.accent.opacity(0.6), lineWidth: 1)
            }
    }
}
