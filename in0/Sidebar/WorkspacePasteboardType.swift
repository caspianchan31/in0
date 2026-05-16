import AppKit

extension NSPasteboard.PasteboardType {
    /// in0 sidebar's drag-reorder pasteboard type. Internal-only: the list
    /// never accepts external drops, and rows only paste their UUID
    /// string. Naming mirrors the .in0Tab type used by the tab bar.
    static let in0Workspace = NSPasteboard.PasteboardType("com.local.in0.workspace")
}
