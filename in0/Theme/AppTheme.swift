import AppKit
import SwiftUI

/// Semantic color tokens. Every view reads from a current `AppTheme`; no
/// view hardcodes a `Color(...)` or `NSColor(...)`.
struct AppTheme: Equatable, Sendable {
    var sidebar: Color
    var canvas: Color
    var foreground: Color
    var textSecondary: Color
    var border: Color
    var borderStrong: Color
    var accent: Color
    var selection: Color

    // Semantic status tints. Read by `TerminalStatusIconView` when painting
    // the success / failed dots. Kept on the theme so themes can override —
    // a high-contrast theme might want pure-saturation greens; a muted
    // theme might prefer washed.
    var success: Color = Color(red: 0.20, green: 0.65, blue: 0.30)
    var danger: Color  = Color(red: 0.85, green: 0.22, blue: 0.22)

    /// Heuristic dark-mode flag. Read by views that spawn into independent
    /// NSWindows (popovers, sheets) and need to set `preferredColorScheme`
    /// explicitly so the new window doesn't inherit the system appearance
    /// — without it a TextField's plate clashes with our chrome.
    var isDark: Bool {
        let ns = NSColor(canvas).usingColorSpace(.sRGB)
        let r = ns?.redComponent ?? 0
        let g = ns?.greenComponent ?? 0
        let b = ns?.blueComponent ?? 0
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 0.5
    }

    /// Settings and sidebar chrome sit on `sidebar`, not on the terminal
    /// canvas. Derive their control appearance from that surface so a dark
    /// terminal theme does not turn the preferences overlay black.
    var sidebarIsDark: Bool {
        let ns = NSColor(sidebar).usingColorSpace(.sRGB)
        let r = ns?.redComponent ?? 0
        let g = ns?.greenComponent ?? 0
        let b = ns?.blueComponent ?? 0
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) < 0.5
    }

    // Companion aliases keep view code readable across SwiftUI and AppKit.
    var textPrimary: Color { foreground }
    var textTertiary: Color { textSecondary.opacity(0.7) }
    var textTertiaryNS: NSColor { NSColor(textTertiary) }
    var successNS: NSColor { NSColor(success) }
    var dangerNS:  NSColor { NSColor(danger) }

    // AppKit-side mirrors. NSColor must be derived; SwiftUI Color → NSColor
    // round-tripping works for asset-style colors but is lossy for opacity
    // changes, so views that need NSColor read these directly.
    var sidebarNS: NSColor { NSColor(sidebar) }
    var canvasNS: NSColor { NSColor(canvas) }
    var foregroundNS: NSColor { NSColor(foreground) }
    var textSecondaryNS: NSColor { NSColor(textSecondary) }
    var borderNS: NSColor { NSColor(border) }
    var borderStrongNS: NSColor { NSColor(borderStrong) }
    var accentNS: NSColor { NSColor(accent) }
    var selectionNS: NSColor { NSColor(selection) }

    static let darkDefault = AppTheme(
        sidebar: Color(red: 0.875, green: 0.882, blue: 0.875),
        canvas: Color(red: 0.035, green: 0.031, blue: 0.043),
        foreground: Color(white: 0.02),
        textSecondary: Color(white: 0.30),
        border: Color(white: 0.72),
        borderStrong: Color(white: 0.08),
        accent: Color(white: 0.02),
        selection: Color(white: 0.78)
    )

    static let lightDefault = AppTheme(
        sidebar: Color(red: 0.97, green: 0.97, blue: 0.96),
        canvas: Color(white: 1.00),
        foreground: Color(white: 0.10),
        textSecondary: Color(white: 0.45),
        border: Color(white: 0.88),
        borderStrong: Color(white: 0.72),
        accent: Color(red: 0.18, green: 0.45, blue: 0.80),
        selection: Color(white: 0.86)
    )
}
