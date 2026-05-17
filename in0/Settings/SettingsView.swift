import SwiftUI

/// Root Settings panel. Replaces macOS's built-in `Settings` Scene chrome
/// (which uses system `TabView`) with a custom horizontal tab bar so the
/// header matches the rest of in0's design. Each section lives in its
/// own file under `Settings/Sections/` — this view only routes between
/// them based on the user's `SettingsSection` selection.
struct SettingsView: View {
    @Environment(ThemeManager.self) private var themeManager
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(\.locale) private var locale
    @State private var selection: SettingsSection

    private let onClose: (() -> Void)?

    init(initialSection: SettingsSection? = nil, onClose: (() -> Void)? = nil) {
        _selection = State(initialValue: initialSection ?? .appearance)
        self.onClose = onClose
    }

    var body: some View {
        let theme = themeManager.currentTheme
        let chromeOpacity = themeManager.contentEffectiveOpacity
        VStack(spacing: 0) {
            SettingsTabBarView(selection: $selection, theme: theme, onClose: onClose)
                .padding(.top, DT.Space.xs)
                .padding(.horizontal, DT.Space.xs)
                .padding(.bottom, DT.Space.xs)

            VStack(spacing: 0) {
                section
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer(theme: theme)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.sidebar.opacity(chromeOpacity))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
            .padding(.horizontal, DT.Space.xs)
            .padding(.bottom, DT.Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.sidebar.opacity(chromeOpacity))
        .foregroundStyle(theme.textPrimary)
        .tint(theme.accent)
        .preferredColorScheme(theme.sidebarIsDark ? .dark : .light)
        .onExitCommand {
            onClose?()
        }
    }

    @ViewBuilder
    private var section: some View {
        switch selection {
        case .appearance:   AppearanceSectionView()
        case .quickActions: QuickActionsSectionView()
        case .plugins:      PluginsSectionView()
        case .agents:       AgentsSectionView()
        case .font:         FontSectionView()
        case .terminal:     TerminalSectionView()
        case .shell:        ShellSectionView()
        case .update:       UpdateSectionView()
        }
    }

    private func footer(theme: AppTheme) -> some View {
        HStack {
            TextLinkButton(
                theme: theme,
                title: String(localized: L10n.Menu.editConfig.withLocale(locale))
            ) {
                configStore.openInEditor()
            }
            Spacer()
            Text(L10n.Settings.footerLive)
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
        }
        .padding(.horizontal, DT.Space.md)
        .padding(.vertical, DT.Space.sm)
        .background(theme.sidebar.opacity(themeManager.contentEffectiveOpacity))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.border.opacity(0.5))
                .frame(height: DT.Stroke.hairline)
        }
    }
}
