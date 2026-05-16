import AppKit
import SwiftUI

/// Text-only link button. Reads as a plain label until hover, which colors
/// it to `textPrimary` and underlines; pressing tints it `textTertiary`.
/// Cursor flips to pointing hand on hover. Used wherever we want a
/// secondary action that shouldn't compete visually with a `.bordered`
/// button.
struct TextLinkButton: View {
    let theme: AppTheme
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .underline(hovering)
                .contentShape(Rectangle())
        }
        .buttonStyle(TextLinkStyle(theme: theme, hovering: hovering))
        .onHover { inside in
            hovering = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

private struct TextLinkStyle: ButtonStyle {
    let theme: AppTheme
    let hovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(color(pressed: configuration.isPressed))
    }

    private func color(pressed: Bool) -> Color {
        if pressed { return theme.textTertiary }
        if hovering { return theme.textPrimary }
        return theme.textSecondary
    }
}
