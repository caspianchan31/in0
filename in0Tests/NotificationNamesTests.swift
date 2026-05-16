import XCTest
@testable import in0

/// Locks the menu-notification raw values so renames or typos in
/// `MenuNotifications.swift` get caught — those strings are also referenced
/// in `Notification.Name` extensions and observers. The pasteboard
/// selectors (⌘C/⌘V/⌘A) deliberately don't route through notifications;
/// they go directly through the responder chain via `NSApp.sendAction`.
final class NotificationNamesTests: XCTestCase {
    func testCoreNotificationRawValues() {
        XCTAssertEqual(Notification.Name.in0NewTab.rawValue,        "in0.menu.newTab")
        XCTAssertEqual(Notification.Name.in0ClosePane.rawValue,     "in0.menu.closePane")
        XCTAssertEqual(Notification.Name.in0SplitVertical.rawValue, "in0.menu.splitVertical")
        XCTAssertEqual(Notification.Name.in0FocusNextPane.rawValue, "in0.menu.focusNextPane")
        XCTAssertEqual(Notification.Name.in0FocusPrevPane.rawValue, "in0.menu.focusPrevPane")
        XCTAssertEqual(Notification.Name.in0SelectNextTab.rawValue, "in0.menu.selectNextTab")
        XCTAssertEqual(Notification.Name.in0SelectTabAtIndex.rawValue, "in0.menu.selectTabAtIndex")
    }
}
