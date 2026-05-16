import AppKit
import Observation
import SwiftUI

/// Owns the active `AppTheme` and republishes when the system appearance
/// changes. Future: also reconcile with ghostty config theme + user override.
@MainActor
@Observable
final class ThemeManager {
    private(set) var currentTheme: AppTheme

    private var appearanceObserver: NSObjectProtocol?

    /// Window and content effects mirrored from the in0 override config.
    /// These intentionally live beside the theme so SwiftUI/AppKit chrome
    /// can react to the same config flush that reloads libghostty.
    private(set) var backgroundOpacity: CGFloat = 1.0
    private(set) var backgroundBlurRadius: CGFloat = 0
    private(set) var contentOpacity: CGFloat = 1.0
    private(set) var contentShadowIntensity: CGFloat = 0

    var contentEffectiveOpacity: CGFloat { backgroundOpacity * contentOpacity }

    /// Last terminal background/foreground reported by ghostty, if any.
    /// When both are present the chrome derives from these instead of the
    /// static default.
    private var terminalBackground: NSColor?
    private var terminalForeground: NSColor?

    init() {
        self.currentTheme = Self.themeForCurrentAppearance()
        observeAppearance()
        // Pull whatever ghostty already has configured (config file + theme)
        // so the chrome doesn't flash a generic dark gray before the first
        // surface broadcasts its colors via the COLOR_CHANGE action.
        reloadFromGhosttyConfig()
    }

    /// Re-read the user's ghostty config + the in0 override file and
    /// re-derive the chrome theme. Callers wire this to
    /// `SettingsConfigStore.onChange` so live edits in Settings flow to
    /// the chrome immediately.
    func reloadFromGhosttyConfig() {
        let colors = GhosttyConfigReader.load()
        guard let bg = colors.background else { return }
        terminalBackground = bg
        terminalForeground = colors.foreground
        currentTheme = Self.derive(background: bg, foreground: colors.foreground)
    }

    /// Called from the GhosttyBridge color_change action. Re-derives the
    /// chrome theme so sidebar/canvas/border track the active terminal.
    func applyTerminalColor(kind: Int32, r: UInt8, g: UInt8, b: UInt8) {
        let color = NSColor(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
        switch kind {
        case -2: terminalBackground = color
        case -1: terminalForeground = color
        default: return
        }
        guard let bg = terminalBackground else { return }
        currentTheme = Self.derive(background: bg, foreground: terminalForeground)
    }

    func applyWindowEffects(
        opacity: CGFloat,
        blurRadius: CGFloat,
        contentOpacity: CGFloat = 1.0,
        contentShadow: CGFloat = 0
    ) {
        let nextOpacity = max(0, min(1, opacity))
        let nextBlur = max(0, min(100, blurRadius))
        let nextContent = max(0, min(1, contentOpacity))
        let nextShadow = max(0, min(1, contentShadow))
        if backgroundOpacity != nextOpacity { backgroundOpacity = nextOpacity }
        if backgroundBlurRadius != nextBlur { backgroundBlurRadius = nextBlur }
        if self.contentOpacity != nextContent { self.contentOpacity = nextContent }
        if contentShadowIntensity != nextShadow { contentShadowIntensity = nextShadow }
    }

    /// Static derivation exposed so unit tests can fuzz the perceptual
    /// math (border luminance landing between bg and fg, etc.) without
    /// having to spin up a full ThemeManager and feed it through a
    /// ghostty action callback.
    static func derive(background bg: NSColor, foreground fg: NSColor?) -> AppTheme {
        let bgLum = bg.relativeLuminance
        let isDark = bgLum < 0.5
        let fgColor = fg ?? (isDark ? NSColor(white: 0.92, alpha: 1) : NSColor(white: 0.10, alpha: 1))
        let canvas = Color(nsColor: bg)
        let sidebar = Color(nsColor: bg.blended(towards: fgColor, by: isDark ? 0.08 : 0.04))
        let foreground = Color(nsColor: fgColor)
        let textSecondary = Color(nsColor: fgColor.withAlphaComponent(0.6))
        let border = Color(nsColor: fgColor.withAlphaComponent(0.20))
        let borderStrong = Color(nsColor: fgColor.withAlphaComponent(0.36))
        let selection = Color(nsColor: fgColor.withAlphaComponent(0.22))
        return AppTheme(
            sidebar: sidebar,
            canvas: canvas,
            foreground: foreground,
            textSecondary: textSecondary,
            border: border,
            borderStrong: borderStrong,
            accent: foreground,
            selection: selection
        )
    }

    // No deinit cleanup: the observer is removed when the process exits.
    // Removing it from a nonisolated deinit would require crossing actors,
    // and ThemeManager lives for the lifetime of the app.

    private func observeAppearance() {
        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.currentTheme = Self.themeForCurrentAppearance()
            }
        }
    }

    private static func themeForCurrentAppearance() -> AppTheme {
        // Default to dark — ghostty's default terminal background is dark, and
        // the chrome should blend with the terminal regardless of system
        // appearance. A future "follow ghostty config" pass can read the
        // user's actual background-color and derive sidebar/canvas from it.
        return .darkDefault
    }
}

private extension NSColor {
    var relativeLuminance: CGFloat {
        guard let rgb = usingColorSpace(.sRGB) else { return 0.5 }
        func linear(_ c: CGFloat) -> CGFloat {
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }

    func blended(towards other: NSColor, by fraction: CGFloat) -> NSColor {
        return blended(withFraction: fraction, of: other) ?? self
    }
}
