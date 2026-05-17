import CoreGraphics
import Foundation
import Observation

@MainActor
@Observable
final class PluginCardStore {
    private let settings: SettingsConfigStore

    private static let kOpen = "in0-plugin-card-sidebar-open"
    private static let kWidth = "in0-plugin-card-sidebar-width"

    var isOpen: Bool
    var width: CGFloat

    init(settings: SettingsConfigStore) {
        self.settings = settings
        self.isOpen = settings.get(Self.kOpen) != "false"
        let rawWidth = settings.get(Self.kWidth).flatMap(Double.init)
        self.width = Self.clamp(CGFloat(rawWidth ?? Double(DT.Layout.pluginCardSidebarWidth)))
    }

    func setOpen(_ open: Bool) {
        guard isOpen != open else { return }
        isOpen = open
        settings.set(Self.kOpen, open ? "true" : "false")
    }

    func toggle() {
        setOpen(!isOpen)
    }

    func setWidth(_ newWidth: CGFloat) {
        let clamped = Self.clamp(newWidth)
        guard abs(width - clamped) > 0.5 else { return }
        width = clamped
        settings.set(Self.kWidth, String(format: "%.0f", Double(clamped)))
    }

    private static func clamp(_ width: CGFloat) -> CGFloat {
        min(max(width, DT.Layout.pluginCardSidebarMinWidth), DT.Layout.pluginCardSidebarMaxWidth)
    }
}
