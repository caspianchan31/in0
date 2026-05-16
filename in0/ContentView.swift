import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(WorkspaceStore.self) private var workspaces
    @Environment(SettingsConfigStore.self) private var configStore
    @Environment(TerminalStatusStore.self) private var statuses
    @Environment(SettingsStore.self) private var settings
    @Environment(QuickActionsStore.self) private var quickActions
    @Environment(UpdateStore.self) private var updateStore
    @Environment(LanguageStore.self) private var language

    @State private var sidebarCollapsed = false
    @State private var showSettings = false
    @State private var pendingSettingsSection: SettingsSection?
    @State private var settingsKeyMonitor: Any?

    var body: some View {
        let t = theme.currentTheme
        let bgOpacity = theme.backgroundOpacity
        let contentOpacity = theme.contentEffectiveOpacity
        let shadow = theme.contentShadowIntensity
        ZStack(alignment: .topLeading) {
            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    SidebarView()
                        .frame(width: DesignTokens.Layout.sidebarWidth)
                        .background(t.sidebar.opacity(bgOpacity))
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                TabBridgeContainer(
                    theme: t,
                    contentOpacity: contentOpacity,
                    shadowIntensity: shadow
                ) {
                    ZStack {
                        TabBridge()
                            .opacity(showSettings ? 0 : 1)
                            .allowsHitTesting(!showSettings)
                        if showSettings {
                            SettingsView(
                                initialSection: pendingSettingsSection,
                                onClose: closeSettings
                            )
                            .id(pendingSettingsSection?.rawValue ?? "settings-default")
                            .environment(settings)
                            .environment(configStore)
                            .environment(quickActions)
                            .environment(theme)
                            .environment(language)
                            .environment(updateStore)
                        }
                    }
                }
                .padding(.top, 28)
                .padding(.leading, sidebarCollapsed ? DT.Space.sm : 0)
                .padding(.trailing, DT.Space.sm)
                .padding(.bottom, DT.Space.sm)
            }

            HStack(spacing: DT.Space.sm) {
                IconButton(theme: t, help: sidebarCollapsed ? "Show sidebar" : "Hide sidebar") {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        sidebarCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14, weight: .semibold))
                }

                if !sidebarCollapsed {
                    IconButton(theme: t, help: "New workspace") {
                        workspaces.addWorkspace(name: "workspace \(workspaces.workspaces.count + 1)")
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                    }
                }
            }
            .foregroundStyle(t.foreground)
            .padding(.leading, headerControlsLeading)
            .padding(.top, DT.Space.sm)
        }
        .background(t.sidebar.opacity(bgOpacity))
        .frame(minWidth: 980, minHeight: 620)
        .background(t.sidebar.opacity(bgOpacity))
        .background(WindowAccessor { window in
            window.appearance = NSAppearance(named: t.sidebarIsDark ? .darkAqua : .aqua)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            window.isOpaque = bgOpacity >= 1.0
            window.backgroundColor = NSColor(t.sidebar).withAlphaComponent(bgOpacity)
            GhosttyBridge.shared.applyWindowBackgroundBlur(to: window)
        })
        .onChange(of: configStore.lines) { _, _ in
            applyConfigDrivenEffects()
        }
        .onAppear {
            applyConfigDrivenEffects()
        }
        .onDisappear {
            removeSettingsKeyMonitor()
        }
        .modifier(MenuNotificationsListener(
            workspaces: workspaces,
            configStore: configStore,
            isSettingsPresented: { showSettings },
            closeSettings: closeSettings
        ))
        .onReceive(NotificationCenter.default.publisher(for: .in0OpenGitTab)) { _ in
            workspaces.ensureGitTab(command: settings.gitViewerCommand)
        }
        .onReceive(NotificationCenter.default.publisher(for: .in0OpenSettings)) { note in
            if let raw = note.userInfo?["section"] as? String,
               let section = SettingsSection(rawValue: raw) {
                pendingSettingsSection = section
            } else {
                pendingSettingsSection = nil
            }
            showSettings = true
        }
        .onChange(of: showSettings) { _, isPresented in
            updateSettingsKeyMonitor(isPresented: isPresented)
        }
        // Auto-mark every focused terminal as "read" so the sidebar dot
        // collapses from filled (unread) to outline (acknowledged) the
        // moment the user looks at the tab. This is what tells the user
        // "I've seen the result" without requiring a manual dismiss.
        .onChange(of: focusedTerminalId) { _, newValue in
            guard let id = newValue else { return }
            statuses.markRead(id)
        }
        .onExitCommand {
            if showSettings {
                closeSettings()
            }
        }
    }

    private func closeSettings() {
        showSettings = false
        pendingSettingsSection = nil
    }

    private var headerControlsLeading: CGFloat {
        if sidebarCollapsed { return 78 }
        return DT.Layout.sidebarWidth - 56
    }

    private func updateSettingsKeyMonitor(isPresented: Bool) {
        if isPresented {
            guard settingsKeyMonitor == nil else { return }
            settingsKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 || Self.isCommandW(event) {
                    closeSettings()
                    return nil
                }
                return event
            }
        } else {
            removeSettingsKeyMonitor()
        }
    }

    private func removeSettingsKeyMonitor() {
        guard let settingsKeyMonitor else { return }
        NSEvent.removeMonitor(settingsKeyMonitor)
        self.settingsKeyMonitor = nil
    }

    private static func isCommandW(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command && event.charactersIgnoringModifiers?.lowercased() == "w"
    }

    private func applyConfigDrivenEffects() {
        let opacity = CGFloat(Double(configStore.get("background-opacity") ?? "") ?? 1.0)
        let blur = CGFloat(Double(configStore.get("background-blur-radius") ?? "") ?? 0)
        let content = CGFloat(Double(configStore.get("in0-content-opacity") ?? "") ?? 1.0)
        let shadow = CGFloat(Double(configStore.get("in0-content-shadow") ?? "") ?? 0)
        let unfocused = CGFloat(Double(configStore.get("unfocused-split-opacity") ?? "") ?? 0.7)
        theme.applyWindowEffects(
            opacity: opacity,
            blurRadius: blur,
            contentOpacity: content,
            contentShadow: shadow
        )
        SplitPaneView.setUnfocusedAlpha(unfocused)
    }

    /// The currently-focused terminal across the active workspace's
    /// active tab. Returns nil during tab-creation transients.
    private var focusedTerminalId: UUID? {
        guard let wsId = workspaces.selectedId,
              let ws = workspaces.workspaces.first(where: { $0.id == wsId }),
              let tabId = ws.selectedTabId,
              let tab = ws.tabs.first(where: { $0.id == tabId }) else {
            return nil
        }
        return tab.focusedTerminalId
    }
}

private struct TabBridgeContainer<Content: View>: View {
    let theme: AppTheme
    let contentOpacity: CGFloat
    let shadowIntensity: CGFloat
    let content: Content

    init(
        theme: AppTheme,
        contentOpacity: CGFloat,
        shadowIntensity: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.theme = theme
        self.contentOpacity = contentOpacity
        self.shadowIntensity = shadowIntensity
        self.content = content()
    }

    var body: some View {
        content
            .background(theme.canvas.opacity(contentOpacity))
            .clipShape(RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous))
            .overlay {
                if shadowIntensity > 0 {
                    RoundedRectangle(cornerRadius: DT.Radius.lg, style: .continuous)
                        .strokeBorder(theme.border.opacity(Double(shadowIntensity) * 0.6), lineWidth: DT.Stroke.hairline)
                }
            }
            .shadow(
                color: .black.opacity(Double(shadowIntensity) * 0.18),
                radius: 6 + shadowIntensity * 8,
                x: 0,
                y: 2
            )
    }
}

/// Connects the Scene-level menu notifications to store mutations. Lives
/// inside ContentView so it can read every store from the environment.
/// Notifications come from `in0App`'s `.commands` block.
private struct MenuNotificationsListener: ViewModifier {
    let workspaces: WorkspaceStore
    let configStore: SettingsConfigStore
    let isSettingsPresented: () -> Bool
    let closeSettings: () -> Void

    func body(content: Content) -> some View {
        content
            // Terminal lifecycle
            .onReceive(NotificationCenter.default.publisher(for: .in0NewTab)) { _ in
                workspaces.addTabToSelected()
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0ClosePane)) { _ in
                if isSettingsPresented() {
                    closeSettings()
                } else {
                    workspaces.closeFocusedPane()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0SplitVertical)) { _ in
                workspaces.splitFocusedInSelected(direction: .vertical)
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0SplitHorizontal)) { _ in
                workspaces.splitFocusedInSelected(direction: .horizontal)
            }
            // Pane focus
            .onReceive(NotificationCenter.default.publisher(for: .in0FocusNextPane)) { _ in
                workspaces.moveFocus(.right)
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0FocusPrevPane)) { _ in
                workspaces.moveFocus(.left)
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0FocusUpPane)) { _ in
                workspaces.moveFocus(.up)
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0FocusDownPane)) { _ in
                workspaces.moveFocus(.down)
            }
            // Tab navigation
            .onReceive(NotificationCenter.default.publisher(for: .in0SelectNextTab)) { _ in
                workspaces.selectNextTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0SelectPrevTab)) { _ in
                workspaces.selectPrevTab()
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0SelectTabAtIndex)) { note in
                if let idx = note.userInfo?["index"] as? Int {
                    workspaces.selectTab(atIndex: idx)
                }
            }
            // Workspace creation
            .onReceive(NotificationCenter.default.publisher(for: .in0BeginCreateWorkspace)) { _ in
                workspaces.addWorkspace(name: "workspace \(workspaces.workspaces.count + 1)")
            }
            // Open config file in default editor
            .onReceive(NotificationCenter.default.publisher(for: .in0EditConfigFile)) { _ in
                configStore.openInEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .in0OpenSettings)) { _ in }
    }
}
