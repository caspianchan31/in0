import AppKit

extension NSPasteboard.PasteboardType {
    /// in0 tab-bar drag-reorder pasteboard type. Internal-only — the tab
    /// bar never accepts external drops, and rows only paste their UUID
    /// string. Lives alongside `.in0Workspace` so both UTIs are owned by
    /// `TabContent/PasteboardTypes.swift` rather than buried in the view.
    static let in0Tab = NSPasteboard.PasteboardType("com.local.in0.tab")
}
