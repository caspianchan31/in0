import AppKit
import SwiftUI

/// Compact icon button used in sidebar/tab-bar chrome. Hover paints a
/// rounded `theme.border` plate; pressed deepens it to `theme.borderStrong`.
/// Matches the hover/selected look of sidebar rows so all chrome
/// affordances feel like the same family.
struct IconButton<Label: View>: View {
    let theme: AppTheme
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(IconButtonHoverStyle(theme: theme, hovering: hovering))
        .help(help)
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct IconButtonHoverStyle: ButtonStyle {
    let theme: AppTheme
    let hovering: Bool

    @Environment(ThemeManager.self) private var themeManager

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: DT.Radius.row, style: .continuous)
                    .fill(plateColor(pressed: configuration.isPressed))
            )
    }

    /// Interaction-state plate. Multiplied by the window's content opacity
    /// so the hover/press tint stays in the same density family as the
    /// chrome behind it — avoids the button popping out at full opacity
    /// when the rest of the chrome is translucent.
    private func plateColor(pressed: Bool) -> Color {
        let opacity = themeManager.contentEffectiveOpacity
        if pressed {
            return theme.borderStrong.opacity(opacity)
        } else if hovering {
            return theme.border.opacity(opacity)
        }
        return .clear
    }
}
