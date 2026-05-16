import SwiftUI

/// Horizontal section picker that sits along the top of the Settings
/// panel. Plain SwiftUI buttons + a selected-underline rule; we explicitly
/// avoid `TabView`'s system tab bar because its chrome doesn't match the
/// rest of the app and SwiftUI's tabItem placement is hard to theme.
struct SettingsTabBarView: View {
    @Binding var selection: SettingsSection
    let theme: AppTheme
    var onClose: (() -> Void)? = nil

    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DT.Space.xs) {
                    ForEach(SettingsSection.allCases) { section in
                        tab(for: section)
                    }
                }
                .padding(DT.Space.xs)
                .padding(.trailing, DT.Space.sm)
            }
            .frame(maxWidth: .infinity)

            if let onClose {
                IconButton(theme: theme, help: "Close settings", action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(theme.textSecondary)
                .keyboardShortcut(.cancelAction)
                .padding(.trailing, DT.Space.xs)
            }
        }
        .frame(height: 34)
        .background(theme.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
    }

    private func tab(for section: SettingsSection) -> some View {
        let selected = (section == selection)
        return Button {
            selection = section
        } label: {
            Text(String(localized: section.label.withLocale(locale)))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(minWidth: 100, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: DT.Radius.md, style: .continuous)
                        .fill(selected ? theme.selection.opacity(0.72) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
