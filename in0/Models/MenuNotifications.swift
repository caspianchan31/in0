import Foundation

/// Decoupled menu-command bus. Menu items live at the SwiftUI Scene level
/// where the environment stores aren't directly reachable; they post one of
/// these notifications, and the right component (ContentView for terminal
/// commands, SidebarView for workspace commands, etc.) listens.
///
/// One notification per action — that keeps each handler small, and avoids
/// the temptation to overload a single "menu" notification with userInfo
/// dictionaries that go stale.
extension Notification.Name {
    // App
    static let in0OpenSettings        = Notification.Name("in0.menu.openSettings")
    static let in0EditConfigFile      = Notification.Name("in0.menu.editConfigFile")
    // File
    static let in0BeginCreateWorkspace = Notification.Name("in0.menu.beginCreateWorkspace")
    // Terminal — tab/pane lifecycle
    static let in0NewTab              = Notification.Name("in0.menu.newTab")
    static let in0ClosePane           = Notification.Name("in0.menu.closePane")
    static let in0SplitVertical       = Notification.Name("in0.menu.splitVertical")
    static let in0SplitHorizontal     = Notification.Name("in0.menu.splitHorizontal")
    // Terminal — focus / nav
    static let in0FocusNextPane       = Notification.Name("in0.menu.focusNextPane")
    static let in0FocusPrevPane       = Notification.Name("in0.menu.focusPrevPane")
    static let in0FocusUpPane         = Notification.Name("in0.menu.focusUpPane")
    static let in0FocusDownPane       = Notification.Name("in0.menu.focusDownPane")
    static let in0SelectNextTab       = Notification.Name("in0.menu.selectNextTab")
    static let in0SelectPrevTab       = Notification.Name("in0.menu.selectPrevTab")
    /// userInfo["index"] = 0-based Int
    static let in0SelectTabAtIndex    = Notification.Name("in0.menu.selectTabAtIndex")
    // Git tab
    static let in0OpenGitTab          = Notification.Name("in0.menu.openGitTab")
}
