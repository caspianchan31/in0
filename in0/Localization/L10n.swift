import Foundation

// MARK: - LocalizedStringResource + locale helper

extension LocalizedStringResource {
    /// Returns a copy with an explicit locale override.
    ///
    /// Use this whenever `String(localized:)` is needed outside of a
    /// `Text(_:)` — e.g. `LabeledContent`, `TextField`, `alert` titles —
    /// so the resolved string honors the SwiftUI `\.locale` environment
    /// rather than `Locale.current`.
    func withLocale(_ locale: Locale) -> LocalizedStringResource {
        var copy = self
        copy.locale = locale
        return copy
    }
}

/// Compile-time namespace for in0's localizable strings. Mirrors the UI
/// module structure.
///
/// - SwiftUI: `Text(L10n.Sidebar.newWorkspace)` (LocalizedStringResource).
/// - AppKit:  `L10n.string("sidebar.newWorkspace")` resolves through the
///   shared LanguageStore's `effectiveBundle`.
///
/// Keys are dotted namespaces; source language is English. Translations
/// live in `Resources/Localizable.xcstrings`. New keys must be added in
/// both this file (for compile-time discoverability) and the catalog (for
/// the actual translation row).
enum L10n {

    // MARK: - AppKit helper

    /// Resolve `key` against the shared store's effective bundle. With
    /// trailing `args`, runs `String(format:)`. Used in AppKit call sites
    /// that can't read `\.locale`.
    @MainActor
    static func string(_ key: String, _ args: CVarArg...) -> String {
        let bundle = LanguageStore.shared.effectiveBundle
        let raw = bundle.localizedString(forKey: key, value: nil, table: nil)
        return args.isEmpty ? raw : String(format: raw, arguments: args)
    }

    // MARK: - QuickActions

    enum QuickActions {
        enum Builtin {
            static let gitui    = LocalizedStringResource("quickActions.builtin.gitui")
            static let claude   = LocalizedStringResource("quickActions.builtin.claude")
            static let codex    = LocalizedStringResource("quickActions.builtin.codex")
            static let opencode = LocalizedStringResource("quickActions.builtin.opencode")
        }
    }

    // MARK: - Settings

    enum Settings {
        static let sectionAppearance   = LocalizedStringResource("settings.section.appearance")
        static let sectionFont         = LocalizedStringResource("settings.section.font")
        static let sectionTerminal     = LocalizedStringResource("settings.section.terminal")
        static let sectionShell        = LocalizedStringResource("settings.section.shell")
        static let sectionQuickActions = LocalizedStringResource("settings.section.quickActions")
        static let sectionAgents       = LocalizedStringResource("settings.section.agents")
        static let sectionUpdate       = LocalizedStringResource("settings.section.update")
        static let footerLive          = LocalizedStringResource("settings.footer.live")

        static let theme               = LocalizedStringResource("settings.appearance.theme")
        static let language            = LocalizedStringResource("settings.appearance.language")
        static let languageSystem      = LocalizedStringResource("settings.language.system")
        static let followsTerminalBg   = LocalizedStringResource("settings.appearance.followsTerminalBackground")
        static let statusIndicators    = LocalizedStringResource("settings.appearance.statusIndicators")
        static let backgroundOpacity   = LocalizedStringResource("settings.appearance.backgroundOpacity")
        static let backgroundBlur      = LocalizedStringResource("settings.appearance.backgroundBlur")
        static let contentOpacity      = LocalizedStringResource("settings.appearance.contentOpacity")
        static let contentShadow       = LocalizedStringResource("settings.appearance.contentShadow")
        static let windowPaddingX      = LocalizedStringResource("settings.appearance.windowPaddingX")
        static let windowPaddingY      = LocalizedStringResource("settings.appearance.windowPaddingY")
        static let cursorStyle         = LocalizedStringResource("settings.appearance.cursorStyle")
        static let cursorBlink         = LocalizedStringResource("settings.appearance.cursorBlink")
        static let unfocusedPaneOpacity = LocalizedStringResource("settings.appearance.unfocusedPaneOpacity")

        static let fontFamily          = LocalizedStringResource("settings.font.family")
        static let fontSize            = LocalizedStringResource("settings.font.size")
        static let fontThicken         = LocalizedStringResource("settings.font.thicken")
        static let fontCustomPlaceholder = LocalizedStringResource("settings.font.customPlaceholder")
        static let fontFooter          = LocalizedStringResource("settings.font.footer")

        static let shellCommand        = LocalizedStringResource("settings.shell.customCommand")
        static let shellPlaceholder    = LocalizedStringResource("settings.shell.defaultPlaceholder")

        enum QuickActions {
            static let heading                  = LocalizedStringResource("settings.quickActions.heading")
            static let headingFooter            = LocalizedStringResource("settings.quickActions.headingFooter")
            static let addCustomButton          = LocalizedStringResource("settings.quickActions.addCustomButton")
            static let customNamePlaceholder    = LocalizedStringResource("settings.quickActions.customNamePlaceholder")
            static let customCommandPlaceholder = LocalizedStringResource("settings.quickActions.customCommandPlaceholder")
            static let deleteCustomTooltip      = LocalizedStringResource("settings.quickActions.deleteCustom.tooltip")
        }

        enum Terminal {
            static let scrollbackLimit      = LocalizedStringResource("settings.terminal.scrollbackLimit")
            static let copyOnSelect         = LocalizedStringResource("settings.terminal.copyOnSelect")
            static let hideMouseWhileTyping = LocalizedStringResource("settings.terminal.hideMouseWhileTyping")
            static let confirmClose         = LocalizedStringResource("settings.terminal.confirmClose")
            static let footer               = LocalizedStringResource("settings.terminal.footer")
        }

        enum Shell {
            static let integration          = LocalizedStringResource("settings.shell.integration")
            static let features             = LocalizedStringResource("settings.shell.features")
            static let gitViewer            = LocalizedStringResource("settings.shell.gitViewer")
            static let gitViewerPlaceholder = LocalizedStringResource("settings.shell.gitViewer.placeholder")
            static let footer               = LocalizedStringResource("settings.shell.footer")
        }

        // Reset row
        static let resetRowLabel    = LocalizedStringResource("settings.reset.rowLabel")
        static let resetButton      = LocalizedStringResource("settings.reset.button")
        static let resetMessage     = LocalizedStringResource("settings.reset.message")
        static let resetAlertTitle  = LocalizedStringResource("settings.reset.alertTitle")
        static let resetCancel      = LocalizedStringResource("settings.reset.cancel")
        // Font picker
        static let fontDefault       = LocalizedStringResource("settings.font.default")
        static let fontCustom        = LocalizedStringResource("settings.font.custom")
        static let fontListButton    = LocalizedStringResource("settings.font.listButton")
        // Theme picker
        static let themeSingle              = LocalizedStringResource("settings.theme.single")
        static let themeFollowSystem        = LocalizedStringResource("settings.theme.followSystem")
        static let themeName                = LocalizedStringResource("settings.theme.name")
        static let themeLight               = LocalizedStringResource("settings.theme.light")
        static let themeDark                = LocalizedStringResource("settings.theme.dark")
        static let themeInherit             = LocalizedStringResource("settings.theme.inherit")
        static let themeSearchPlaceholder   = LocalizedStringResource("settings.theme.searchPlaceholder")

        enum Agents {
            static let notificationsTitle  = LocalizedStringResource("settings.agents.notificationsTitle")
            static let notificationsFooter = LocalizedStringResource("settings.agents.notificationsFooter")
            static let resumeTitle         = LocalizedStringResource("settings.agents.resumeTitle")
            static let resumeFooter        = LocalizedStringResource("settings.agents.resumeFooter")
            static let claude              = LocalizedStringResource("settings.agents.claude")
            static let codex               = LocalizedStringResource("settings.agents.codex")
            static let opencode            = LocalizedStringResource("settings.agents.opencode")
            static let betaBadge           = LocalizedStringResource("settings.agents.betaBadge")
        }

        enum Update {
            static let currentVersion    = LocalizedStringResource("settings.update.currentVersion")
            static let status            = LocalizedStringResource("settings.update.status")
            static let action            = LocalizedStringResource("settings.update.action")
            static let checkForUpdates   = LocalizedStringResource("settings.update.checkForUpdates")
            static let checking          = LocalizedStringResource("settings.update.checking")
            static let upToDate          = LocalizedStringResource("settings.update.upToDate")
            static let unavailable       = LocalizedStringResource("settings.update.unavailable")
            static let downloadInstall   = LocalizedStringResource("settings.update.downloadInstall")
            static let skipThisVersion   = LocalizedStringResource("settings.update.skipThisVersion")
            static let dismiss           = LocalizedStringResource("settings.update.dismiss")
            static let downloading       = LocalizedStringResource("settings.update.downloading")
            static let installing        = LocalizedStringResource("settings.update.installing")
            static let retry             = LocalizedStringResource("settings.update.retry")
        }
    }

    // MARK: - Menu

    enum Menu {
        static let newTab          = LocalizedStringResource("menu.newTab")
        static let closeTab        = LocalizedStringResource("menu.closeTab")
        static let splitRight      = LocalizedStringResource("menu.splitRight")
        static let splitDown       = LocalizedStringResource("menu.splitDown")
        static let focusLeft       = LocalizedStringResource("menu.focusLeft")
        static let focusRight      = LocalizedStringResource("menu.focusRight")
        static let focusUp         = LocalizedStringResource("menu.focusUp")
        static let focusDown       = LocalizedStringResource("menu.focusDown")
        static let settings        = LocalizedStringResource("menu.settings")
        static let editConfig      = LocalizedStringResource("menu.editConfig")
    }

    // MARK: - App

    enum App {
        static let ghosttyNotFoundTitle  = LocalizedStringResource("app.ghostty.notFound.title")
        static let ghosttyNotFoundDetail = LocalizedStringResource("app.ghostty.notFound.detail")
    }
}
