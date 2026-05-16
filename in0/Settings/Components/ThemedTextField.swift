import SwiftUI

/// TextField visual style that respects the active theme. The system's
/// `.roundedBorder` style ships a fixed dark-gray plate that clashes with
/// our chrome colors; this variant uses the theme's `sidebar` fill +
/// `border` hairline so text inputs look like first-class chrome elements.
struct ThemedTextFieldStyle: ViewModifier {
    let theme: AppTheme

    @Environment(ThemeManager.self) private var themeManager

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            // LabeledContent's value column trails by default and `.plain`
            // inherits that; force leading so user input flows L→R.
            .multilineTextAlignment(.leading)
            .foregroundColor(theme.textPrimary)
            .padding(.horizontal, DT.Space.sm)
            .padding(.vertical, DT.Space.xs + 1)
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(theme.sidebar.opacity(themeManager.contentEffectiveOpacity))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .strokeBorder(theme.border.opacity(themeManager.contentEffectiveOpacity), lineWidth: DT.Stroke.hairline * 0.5)
            )
    }
}

extension View {
    func themedTextField(_ theme: AppTheme) -> some View {
        modifier(ThemedTextFieldStyle(theme: theme))
    }
}
