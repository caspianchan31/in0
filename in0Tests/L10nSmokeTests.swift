import XCTest
@testable import in0

/// Schema-level sanity check on the localization catalog. Each compile-
/// time L10n key must resolve to a non-empty string in *every* shipped
/// language; otherwise a missing translation would render as the raw
/// key in production ("MENU.NEWTAB" instead of "New Tab").
@MainActor
final class L10nSmokeTests: XCTestCase {

    private let languages = ["en", "zh-Hans"]

    /// Every key listed in the namespace below is checked against every
    /// language in `languages`. Keep this in lock-step with the
    /// LocalizedStringResource constants in `Localization/L10n.swift`.
    private let keys: [String] = [
        // QuickActions
        "quickActions.builtin.gitui",
        "quickActions.builtin.claude",
        "quickActions.builtin.codex",
        "quickActions.builtin.opencode",
        // Settings sections
        "settings.section.appearance",
        "settings.section.font",
        "settings.section.terminal",
        "settings.section.shell",
        "settings.section.quickActions",
        "settings.section.agents",
        "settings.section.update",
        "settings.footer.live",
        // Appearance / Font / Shell
        "settings.appearance.theme",
        "settings.appearance.language",
        "settings.language.system",
        "settings.appearance.followsTerminalBackground",
        "settings.appearance.statusIndicators",
        "settings.appearance.backgroundOpacity",
        "settings.appearance.backgroundBlur",
        "settings.appearance.contentOpacity",
        "settings.appearance.contentShadow",
        "settings.appearance.windowPaddingX",
        "settings.appearance.windowPaddingY",
        "settings.appearance.cursorStyle",
        "settings.appearance.cursorBlink",
        "settings.appearance.unfocusedPaneOpacity",
        "settings.font.family",
        "settings.font.size",
        "settings.font.thicken",
        "settings.font.customPlaceholder",
        "settings.font.footer",
        "settings.font.default",
        "settings.font.custom",
        "settings.font.listButton",
        "settings.shell.customCommand",
        "settings.shell.defaultPlaceholder",
        "settings.shell.integration",
        "settings.shell.features",
        "settings.shell.gitViewer",
        "settings.shell.gitViewer.placeholder",
        "settings.shell.footer",
        "settings.terminal.scrollbackLimit",
        "settings.terminal.copyOnSelect",
        "settings.terminal.hideMouseWhileTyping",
        "settings.terminal.confirmClose",
        "settings.terminal.footer",
        "settings.update.currentVersion",
        "settings.update.status",
        "settings.update.action",
        "settings.update.checkForUpdates",
        "settings.update.checking",
        "settings.update.upToDate",
        "settings.update.unavailable",
        "settings.update.downloadInstall",
        "settings.update.skipThisVersion",
        "settings.update.dismiss",
        "settings.update.downloading",
        "settings.update.installing",
        "settings.update.retry",
        // Quick Actions Settings
        "settings.quickActions.heading",
        "settings.quickActions.headingFooter",
        "settings.quickActions.addCustomButton",
        "settings.quickActions.customNamePlaceholder",
        "settings.quickActions.customCommandPlaceholder",
        "settings.quickActions.deleteCustom.tooltip",
        // Agents
        "settings.agents.notificationsTitle",
        "settings.agents.notificationsFooter",
        "settings.agents.resumeTitle",
        "settings.agents.resumeFooter",
        "settings.agents.claude",
        "settings.agents.codex",
        "settings.agents.opencode",
        "settings.agents.betaBadge",
        // Reset row
        "settings.reset.rowLabel",
        "settings.reset.button",
        "settings.reset.message",
        "settings.reset.alertTitle",
        "settings.reset.cancel",
        // Theme picker
        "settings.theme.single",
        "settings.theme.followSystem",
        "settings.theme.name",
        "settings.theme.light",
        "settings.theme.dark",
        "settings.theme.inherit",
        "settings.theme.searchPlaceholder",
        // Sidebar
        "sidebar.row.rename",
        "sidebar.row.delete",
        "sidebar.row.commandPanel.editTitle",
        // Menu
        "menu.newTab",
        "menu.closeTab",
        "menu.splitRight",
        "menu.splitDown",
        "menu.focusLeft",
        "menu.focusRight",
        "menu.focusUp",
        "menu.focusDown",
        "menu.settings",
        "menu.editConfig",
        // App
        "app.ghostty.notFound.title",
        "app.ghostty.notFound.detail",
    ]

    func testEveryKeyHasNonEmptyValueInEveryLanguage() {
        for lang in languages {
            guard let lprojPath = Bundle.main.path(forResource: lang, ofType: "lproj"),
                  let bundle = Bundle(path: lprojPath) else {
                XCTFail("\(lang).lproj missing from bundle — check Localizable.xcstrings build phase")
                continue
            }
            for key in keys {
                let value = bundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertFalse(
                    value.isEmpty,
                    "\(lang) localization for `\(key)` is empty"
                )
                XCTAssertNotEqual(
                    value, key,
                    "\(lang) localization for `\(key)` falls back to the key itself"
                )
            }
        }
    }
}
