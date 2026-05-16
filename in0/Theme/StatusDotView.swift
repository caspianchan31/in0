import SwiftUI

/// SwiftUI wrapper around the AppKit `TerminalStatusIconView`. SidebarView
/// (SwiftUI) hands it a status + theme; the wrapper bridges into the
/// CALayer-based icon so the rotation animation runs at native frame
/// rate. Kept thin — all visual logic lives in `TerminalStatusIconView`.
struct StatusDotView: NSViewRepresentable {
    let status: TerminalStatus
    let theme: AppTheme
    var size: CGFloat = TerminalStatusIconView.size

    func makeNSView(context: Context) -> TerminalStatusIconView {
        let v = TerminalStatusIconView(frame: .zero)
        v.update(status: status, theme: theme)
        return v
    }

    func updateNSView(_ nsView: TerminalStatusIconView, context: Context) {
        nsView.update(status: status, theme: theme)
    }
}
