import AppKit
import SwiftUI

@main
struct in0App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var theme = ThemeManager()
    @State private var workspaces = WorkspaceStore()
    @State private var pwds = TerminalPwdStore.shared
    @State private var statuses = TerminalStatusStore()
    @State private var metadata = WorkspaceMetadataStore()
    @State private var settings: SettingsStore
    @State private var configStore: SettingsConfigStore
    @State private var language = LanguageStore.shared
    @State private var quickActions: QuickActionsStore
    @State private var updateStore = UpdateStore()

    init() {
        // 1. Disable NSWindow's automatic native tab bar. in0 renders its own
        //    tab strip; otherwise AppKit hijacks ⌘T for "New Tab in Window"
        //    and overlays a duplicate tab bar.
        NSWindow.allowsAutomaticWindowTabbing = false

        // 2. Bring libghostty up. Failure is non-fatal — the WindowGroup
        //    below switches to GhosttyMissingView so we don't crash.
        let ok = GhosttyBridge.shared.initialize()
        if !ok { NSLog("in0: libghostty initialization failed") }

        // 3. QuickActionsStore depends on SettingsConfigStore; build the
        //    config store here so we can hand it in.
        let cfg = SettingsConfigStore()
        let actions = QuickActionsStore(settings: cfg)
        Self.seedBuiltinQuickActionsIfNeeded(actions, configStore: cfg)
        _configStore = State(initialValue: cfg)
        _quickActions = State(initialValue: actions)
        _settings = State(initialValue: SettingsStore(configStore: cfg))
    }

    var body: some Scene {
        // Touch the language store's `tick` so Commands rebuild when the
        // user switches UI language (LocalizedStringResource is captured at
        // build time, not eagerly observed).
        let _ = language.tick

        WindowGroup {
            if GhosttyBridge.shared.isInitialized {
                ContentView()
                    .environment(theme)
                    .environment(workspaces)
                    .environment(pwds)
                    .environment(statuses)
                    .environment(metadata)
                    .environment(settings)
                    .environment(configStore)
                    .environment(language)
                    .environment(quickActions)
                    .environment(updateStore)
                    .environment(\.locale, language.locale)
                    .onAppear {
                        SparkleBridge.shared.store = updateStore
                        SparkleBridge.shared.start()
                        appDelegate.attach(
                            workspaces: workspaces,
                            pwds: pwds,
                            statuses: statuses,
                            metadata: metadata,
                            theme: theme,
                            settings: settings,
                            configStore: configStore,
                            quickActions: quickActions
                        )
                    }
            } else {
                GhosttyMissingView()
                    .environment(language)
                    .environment(\.locale, language.locale)
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
        .commands {
            appCommands
            fileCommands
            stripped
            editCommands
            terminalCommands
            agentCommands
        }
        #if compiler(>=5.9)
        Settings {
            SettingsView()
                .environment(settings)
                .environment(configStore)
                .environment(quickActions)
                .environment(theme)
                .environment(language)
                .environment(updateStore)
                .environment(\.locale, language.locale)
        }
        #endif
    }

    @MainActor
    private static func seedBuiltinQuickActionsIfNeeded(
        _ actions: QuickActionsStore,
        configStore: SettingsConfigStore
    ) {
        let key = "in0.didSeedQuickActions.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        for builtin in BuiltinQuickAction.allCases {
            actions.setEnabled(builtin.id, true)
        }
        configStore.save()
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: - Menu builders
    //
    // Split into separate properties to keep each block under the
    // @CommandsBuilder 10-element tuple limit and easy to scan.

    @CommandsBuilder private var appCommands: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button(String(localized: L10n.Menu.settings.withLocale(language.locale))) {
                post(.in0OpenSettings)
            }
            .keyboardShortcut(",", modifiers: .command)
            Button(String(localized: L10n.Menu.editConfig.withLocale(language.locale))) {
                post(.in0EditConfigFile)
            }
        }
    }

    @CommandsBuilder private var fileCommands: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(String(localized: L10n.Menu.newTab.withLocale(language.locale))) {
                post(.in0NewTab)
            }
            .keyboardShortcut("t", modifiers: .command)
            Button("New Workspace") {
                post(.in0BeginCreateWorkspace)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    /// Strip macOS auto-injected menu groups that don't apply to a terminal
    /// workspace app. Each replacing-with-EmptyView call deletes the group
    /// outright.
    @CommandsBuilder private var stripped: some Commands {
        CommandGroup(replacing: .saveItem)          { EmptyView() }
        CommandGroup(replacing: .undoRedo)          { EmptyView() }
        CommandGroup(replacing: .textEditing)       { EmptyView() }
        CommandGroup(replacing: .textFormatting)    { EmptyView() }
        CommandGroup(replacing: .toolbar)           { EmptyView() }
        CommandGroup(replacing: .windowArrangement) { EmptyView() }
        CommandGroup(replacing: .help) {
            Button("Help") {}.disabled(true)
        }
    }

    /// Edit menu: dispatch via responder chain (`NSApp.sendAction`) so that
    /// when the first responder is an NSText (sidebar/tab inline rename,
    /// Settings TextFields), ⌘V hits the system paste handler. When the
    /// terminal surface is the first responder, GhosttyTerminalView's own
    /// `paste(_:)` selector catches it and forwards to ghostty. Posting a
    /// notification here would steal ⌘V from every TextField in the app.
    @CommandsBuilder private var editCommands: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Copy") {
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("c", modifiers: .command)
            Button("Paste") {
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("v", modifiers: .command)
            Button("Select All") {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
            .keyboardShortcut("a", modifiers: .command)
        }
    }

    @CommandsBuilder private var terminalCommands: some Commands {
        CommandMenu("Terminal") {
            Button("Close Pane") { post(.in0ClosePane) }
                .keyboardShortcut("w", modifiers: .command)
            Divider()
            Button(String(localized: L10n.Menu.splitRight.withLocale(language.locale))) { post(.in0SplitVertical) }
                .keyboardShortcut("d", modifiers: .command)
            Button(String(localized: L10n.Menu.splitDown.withLocale(language.locale))) { post(.in0SplitHorizontal) }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button(String(localized: L10n.Menu.focusLeft.withLocale(language.locale))) { post(.in0FocusPrevPane) }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button(String(localized: L10n.Menu.focusRight.withLocale(language.locale))) { post(.in0FocusNextPane) }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
            Button(String(localized: L10n.Menu.focusUp.withLocale(language.locale))) { post(.in0FocusUpPane) }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            Button(String(localized: L10n.Menu.focusDown.withLocale(language.locale))) { post(.in0FocusDownPane) }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            Divider()
            Button("Open Git Tab") { post(.in0OpenGitTab) }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            Divider()
            Button("Select Next Tab") { post(.in0SelectNextTab) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Select Previous Tab") { post(.in0SelectPrevTab) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Divider()
            ForEach(1...9, id: \.self) { idx in
                Button("Tab \(idx)") {
                    NotificationCenter.default.post(
                        name: .in0SelectTabAtIndex,
                        object: nil,
                        userInfo: ["index": idx - 1]
                    )
                }
                .keyboardShortcut(KeyEquivalent(Character(String(idx))), modifiers: .command)
            }
        }
    }

    @CommandsBuilder private var agentCommands: some Commands {
        CommandMenu("Agents") {
            Button("Reveal Agent Hooks in Finder") { revealAgentHooks() }
            Button("Copy bash rc Snippet")  { copyBootstrapSnippet(.bash) }
            Button("Copy zsh rc Snippet")   { copyBootstrapSnippet(.zsh) }
            Button("Copy fish rc Snippet")  { copyBootstrapSnippet(.fish) }
            Divider()
            Button("Check for Updates…") {
                SparkleBridge.shared.checkForUpdates(silently: false)
            }
        }
    }

    @MainActor
    private func revealAgentHooks() {
        guard let hooksDir = GhosttyBridge.shared.defaultEnv["IN0_AGENT_HOOKS_DIR"] else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: hooksDir)])
    }

    @MainActor
    private func copyBootstrapSnippet(_ shell: BootstrapShell) {
        let snippet = shell.snippet
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet, forType: .string)
        let alert = NSAlert()
        alert.messageText = "\(shell.displayName) snippet copied"
        alert.informativeText = "Paste into \(shell.rcPath); restart your shell. zsh sessions launched from in0 auto-activate via the ZDOTDIR shim and don't need this step."
        alert.runModal()
    }

    enum BootstrapShell {
        case bash, zsh, fish
        var displayName: String { self == .bash ? "bash" : self == .zsh ? "zsh" : "fish" }
        var rcPath: String { self == .bash ? "~/.bashrc" : self == .zsh ? "~/.zshrc" : "~/.config/fish/config.fish" }
        var snippet: String {
            switch self {
            case .bash, .zsh:
                let file = self == .bash ? "bootstrap.bash" : "bootstrap.zsh"
                return "[ -f \"$IN0_AGENT_HOOKS_DIR/\(file)\" ] && source \"$IN0_AGENT_HOOKS_DIR/\(file)\""
            case .fish:
                return """
                if set -q IN0_AGENT_HOOKS_DIR
                    source "$IN0_AGENT_HOOKS_DIR/bootstrap.fish"
                end
                """
            }
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var refresher: MetadataRefresher?
    private var listener: HookSocketListener?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Drop AppKit's auto-injected top-level menus that don't apply:
        // - Format: font / text submenus, text-editor-only
        // - View: toolbar / fullscreen items; users can still hit ⌃⌘F for fullscreen
        if let mainMenu = NSApp.mainMenu {
            let unwanted: Set<String> = ["Format", "View"]
            mainMenu.items.removeAll { unwanted.contains($0.title) }
            // Even with allowsAutomaticWindowTabbing = false, AppKit can
            // still inject "Show Tab Bar" / "Show All Tabs" entries that
            // bind ⌘T. Walk every submenu and disable those shortcuts.
            walk(menu: mainMenu) { item in
                switch item.action {
                case #selector(NSWindow.toggleTabBar(_:)),
                     #selector(NSWindow.toggleTabOverview(_:)):
                    item.keyEquivalent = ""
                    item.keyEquivalentModifierMask = []
                    item.isHidden = true
                default:
                    break
                }
            }
        }
    }

    private func walk(menu: NSMenu, _ visit: (NSMenuItem) -> Void) {
        for item in menu.items {
            visit(item)
            if let submenu = item.submenu { walk(menu: submenu, visit) }
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Ghostty is brought up in `in0App.init()` now (so the SwiftUI scene
        // can branch on success). Here we wire the bundled agent-hooks
        // directory into every surface's environment — the wrappers under
        // `agent-hooks/` shadow the user's claude/codex/opencode binaries
        // and inject the in0 hook config at exec time. Zsh shells pick up
        // bootstrap automatically via the ZDOTDIR shim (see `newSurface`);
        // bash and fish users source `bootstrap.bash` / `bootstrap.fish`
        // from their rc once.
        if let bundledHooks = Bundle.main.resourceURL?.appendingPathComponent("agent-hooks").path,
           FileManager.default.fileExists(atPath: bundledHooks) {
            GhosttyBridge.shared.defaultEnv["IN0_AGENT_HOOKS_DIR"] = bundledHooks
        } else {
            NSLog("in0: bundled agent-hooks missing — agent status hooks disabled")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GhosttyBridge.shared.teardown()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Wires the @State stores from in0App into the long-lived services
    /// owned by the delegate. Called once from ContentView.onAppear.
    @MainActor
    func attach(
        workspaces: WorkspaceStore,
        pwds: TerminalPwdStore,
        statuses: TerminalStatusStore,
        metadata: WorkspaceMetadataStore,
        theme: ThemeManager,
        settings: SettingsStore,
        configStore: SettingsConfigStore,
        quickActions: QuickActionsStore
    ) {
        guard refresher == nil else { return }

        // PWD inheritance: when WorkspaceStore creates a new terminal via
        // `addTab` or `splitFocused`, copy the source pane's pwd over so
        // the freshly spawned shell starts where the user was. Without
        // this, every new split lands at $HOME — surprising when you
        // wanted "the same place, side by side".
        workspaces.inheritPwdPolicy = { [weak pwds] src, dst in
            pwds?.inherit(from: src, to: dst)
        }
        workspaces.terminalCleanup = { [weak pwds, weak statuses] terminalId in
            pwds?.forget(terminalId: terminalId)
            statuses?.remove(terminalId)
            ResumeStore.shared.clear(terminalId: terminalId)
        }

        // Wire the StartupCommandResolver in one place. Every new terminal
        // created by WorkspaceStore (addTab / splitFocused / launchInNewTab)
        // runs through this hook, which decides the initial command using
        // Quick Action lookup → agent resume → workspace default precedence.
        workspaces.startupCommandPolicy = { [weak quickActions, weak settings] terminalId, tab, workspace in
            let peeked = ResumeStore.shared.peek(terminalId: terminalId)
            let resolved = StartupCommandResolver.resolve(
                terminalId: terminalId,
                tab: tab,
                workspaceDefaultCommand: workspace.defaultCommand,
                quickActionCommand: { id in quickActions?.command(for: id) },
                isResumeEnabled: { agent in settings?.prefs(for: agent).resumeOnLaunch ?? false },
                pendingPrefill: peeked
            )
            // Only burn the persisted resume command if the resolver
            // actually decided to replay it. Otherwise leave it for the
            // next launch — turning Resume off shouldn't lose state.
            if let resolved, let peeked, resolved == peeked {
                _ = ResumeStore.shared.consume(terminalId: terminalId)
            }
            return resolved
        }

        GhosttyBridge.shared.onPwdChanged = { [weak pwds] terminalId, pwd in
            pwds?.setPwd(pwd, for: terminalId)
        }
        GhosttyBridge.shared.onScrollbar = { _, _, _, _ in
            // Per-surface NSView is updated directly inside the action callback.
        }
        GhosttyBridge.shared.onColorChange = { [weak theme, weak settings] kind, r, g, b in
            guard settings?.snapshot.followsTerminalBackground ?? true else { return }
            theme?.applyTerminalColor(kind: kind, r: r, g: g, b: b)
        }
        // SettingsConfigStore writes pass through to the same file ghostty
        // reads from; re-derive the chrome theme and let QuickActions pick
        // up any external edits on every debounced flush.
        configStore.onChange = { [weak theme, weak quickActions] in
            GhosttyBridge.shared.reloadConfig()
            theme?.reloadFromGhosttyConfig()
            quickActions?.reloadFromSettings()
        }

        let dispatcher = HookDispatcher(store: statuses, settings: settings)
        let listener = HookSocketListener(dispatcher: dispatcher)
        listener.start()
        GhosttyBridge.shared.defaultEnv["IN0_HOOK_SOCK"] = listener.socketPath
        self.listener = listener

        let refresher = MetadataRefresher(workspaces: workspaces, pwds: pwds, metadata: metadata)
        refresher.start()
        self.refresher = refresher
    }
}
