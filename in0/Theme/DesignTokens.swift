import AppKit
import SwiftUI

/// Numeric and color primitives. Themes pick from these; views never
/// hardcode raw values.
enum DesignTokens {
    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let row: CGFloat = 6
    }

    enum Stroke {
        static let hairline: CGFloat = 1
    }

    enum Layout {
        static let sidebarWidth: CGFloat = 300
        static let pluginCardSidebarWidth: CGFloat = 360
        static let pluginCardSidebarMinWidth: CGFloat = 300
        static let pluginCardSidebarMaxWidth: CGFloat = 460
        static let terminalContentMinWidth: CGFloat = 520
        static let sidebarContentLeadingInset: CGFloat = 0
        static let tabBarHeight: CGFloat = 34
        static let rowHeight: CGFloat = 42
    }

    /// UI typography. Sizes deliberately stay in the 10–13 pt band so the
    /// chrome scans as compact without ever looking jaggy on Retina.
    enum Font {
        static var micro:  NSFont { .systemFont(ofSize: 10, weight: .regular) }
        static var microB: NSFont { .systemFont(ofSize: 10, weight: .semibold) }
        static var small:  NSFont { .systemFont(ofSize: 11, weight: .regular) }
        static var smallB: NSFont { .systemFont(ofSize: 11, weight: .medium) }
        static var body:   NSFont { .systemFont(ofSize: 12, weight: .regular) }
        static var bodyB:  NSFont { .systemFont(ofSize: 12, weight: .semibold) }
        static var title:  NSFont { .systemFont(ofSize: 13, weight: .semibold) }
        static var mono:   NSFont { .monospacedSystemFont(ofSize: 10, weight: .regular) }
    }
}

/// Short alias matching the convention in companion code (`DT.Space.xxs`
/// reads better in dense view layouts than `DesignTokens.Spacing.xxs`).
enum DT {
    typealias Space = DesignTokens.Spacing
    typealias Radius = DesignTokens.Radius
    typealias Stroke = DesignTokens.Stroke
    typealias Layout = DesignTokens.Layout
    typealias Font   = DesignTokens.Font
}
